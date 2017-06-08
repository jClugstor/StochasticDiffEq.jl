@inline function perform_step!(integrator,cache::EMConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  u = @muladd uprev .+ dt.*integrator.f(t,uprev) .+ integrator.g(t,uprev).*W.dW
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::EMCache,f=integrator.f)
  @unpack rtmp1,rtmp2,rtmp3 = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.f(t,uprev,rtmp1)
  integrator.g(t,uprev,rtmp2)

  if is_diagonal_noise(integrator.sol.prob)
    @tight_loop_macros for i in eachindex(u)
      @inbounds rtmp2[i]*=W.dW[i] # rtmp2 === rtmp3
    end
  else
    A_mul_B!(rtmp3,rtmp2,W.dW)
  end

  #@. u = @muladd uprev + dt*rtmp1 + rtmp3
  @tight_loop_macros for i in eachindex(u)
    @inbounds u[i] = @muladd uprev[i] + dt*rtmp1[i] + rtmp3[i]
  end
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::EulerHeunConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  ftmp = integrator.f(t,uprev)
  gtmp = integrator.g(t,uprev)
  tmp = @. @muladd uprev + ftmp.*dt + gtmp.*W.dW
  u = @muladd uprev .+ (1/2).*dt.*(ftmp.+integrator.f(t+dt,tmp)) .+ (1/2).*(gtmp.+integrator.g(t+dt,tmp)).*W.dW
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::EulerHeunCache,f=integrator.f)
  @unpack ftmp1,ftmp2,gtmp1,gtmp2,tmp,nrtmp = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.f(t,uprev,ftmp1)
  integrator.g(t,uprev,gtmp1)

  if is_diagonal_noise(integrator.sol.prob)
    #@. nrtmp=gtmp1*W.dW
    @tight_loop_macros for i in eachindex(u)
      @inbounds nrtmp[i]=gtmp1[i]*W.dW[i]
    end
  else
    A_mul_B!(nrtmp,gtmp1,W.dW)
  end

  #@. tmp = @muladd uprev + ftmp1*dt + nrtmp
  @tight_loop_macros for i in eachindex(u)
    @inbounds tmp[i] = @muladd uprev[i] + ftmp1[i]*dt + nrtmp[i]
  end

  integrator.f(t+dt,tmp,ftmp2)
  integrator.g(t+dt,tmp,gtmp2)

  if is_diagonal_noise(integrator.sol.prob)
    #@. nrtmp=(1/2)*W.dW*(gtmp1+gtmp2)
    @tight_loop_macros for i in eachindex(u)
      @inbounds dWo2 = (1/2)*W.dW[i]
      @inbounds nrtmp[i]=dWo2*(gtmp1[i]+gtmp2[i])
    end
  else
    #@. gtmp1 = (1/2)*(gtmp1+gtmp2)
    @tight_loop_macros for i in eachindex(gtmp1)
      @inbounds gtmp1[i] = (1/2)*(gtmp1[i]+gtmp2[i])
    end
    A_mul_B!(nrtmp,gtmp1,W.dW)
  end

  dto2 = dt*(1/2)
  #@. u = @muladd uprev + dto2*(ftmp1+ftmp2) + nrtmp
  @tight_loop_macros for i in eachindex(u)
    @inbounds u[i] = @muladd uprev[i] + dto2*(ftmp1[i]+ftmp2[i]) + nrtmp[i]
  end
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::RandomEMConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  u = @muladd uprev .+ dt.*integrator.f(t,uprev,W.dW)
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::RandomEMCache,f=integrator.f)
  @unpack rtmp = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.f(t,uprev,W.dW,rtmp)
  #@. u = @muladd uprev + dt*rtmp
  @tight_loop_macros for i in eachindex(u)
    @inbounds u[i] = @muladd uprev[i] + dt*rtmp[i]
  end
  @pack integrator = t,dt,u
end

@inline function perform_step!(integrator,cache::RKMilConstantCache,f=integrator.f)
  @unpack t,dt,uprev,u,W = integrator
  K = @muladd uprev .+ dt.*integrator.f(t,uprev)
  L = integrator.g(t,uprev)
  utilde = @.  K + L*integrator.sqdt
  if alg_interpretation(integrator.alg) == :Ito
    mil_correction = (integrator.g(t,utilde).-L)./(2 .* integrator.sqdt).*(W.dW.^2 .- dt)
  elseif alg_interpretation(integrator.alg) == :Stratonovich
    mil_correction = W.dW.*(integrator.g(t,utilde).+L)./2
  end
  u = @. K+L*W.dW+mil_correction
  if integrator.opts.adaptive
    integrator.EEst = integrator.opts.internalnorm(@.(mil_correction/(@muladd(integrator.opts.abstol + max.(abs(uprev),abs(u))*integrator.opts.reltol))))
  end
  @pack integrator = t,dt,u
end

#=
@inline function perform_step!(integrator,cache::RKMilCache,f=integrator.f)
  @unpack du1,du2,K,tmp,L = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.f(t,uprev,du1)
  integrator.g(t,uprev,L)
  @. K = @muladd uprev + dt*du1
  @. tmp = @muladd K + L*integrator.sqdt
  integrator.g(t,tmp,du2)
  if alg_interpretation(integrator.alg) == :Ito
    @. tmp = (du2-L)/(2integrator.sqdt)*(W.dW^2 - dt)
  elseif alg_interpretation(integrator.alg) == :Stratonovich
    @. tmp = (du2-L)/(2integrator.sqdt)*(W.dW^2)
  end
  @. u = K+L*W.dW + tmp
  if integrator.opts.adaptive
    @. tmp = @muladd(tmp)/@muladd(integrator.opts.abstol + max(abs(uprev),abs(u))*integrator.opts.reltol)
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end
=#

@inline function perform_step!(integrator,cache::RKMilCache,f=integrator.f)
  @unpack du1,du2,K,tmp,L = cache
  @unpack t,dt,uprev,u,W = integrator
  integrator.f(t,uprev,du1)
  integrator.g(t,uprev,L)
  @tight_loop_macros for i in eachindex(u)
    @inbounds K[i] = @muladd uprev[i] + dt*du1[i]
    @inbounds tmp[i] = @muladd K[i] + L[i]*integrator.sqdt
  end
  integrator.g(t,tmp,du2)
  if alg_interpretation(integrator.alg) == :Ito
    @tight_loop_macros for i in eachindex(u)
      @inbounds tmp[i] = (du2[i]-L[i])/(2integrator.sqdt)*(W.dW[i].^2 - dt)
    end
  elseif alg_interpretation(integrator.alg) == :Stratonovich
    @tight_loop_macros for i in eachindex(u)
      @inbounds tmp[i] = (du2[i]-L[i])/(2integrator.sqdt)*(W.dW[i].^2)
    end
  end
  @tight_loop_macros for i in eachindex(u)
    @inbounds u[i] = K[i]+L[i]*W.dW[i] + tmp[i]
  end
  if integrator.opts.adaptive
    @tight_loop_macros for i in eachindex(u)
      @inbounds tmp[i] = @muladd(tmp[i])/@muladd(integrator.opts.abstol + max(abs(uprev[i]),abs(u[i]))*integrator.opts.reltol)
    end
    integrator.EEst = integrator.opts.internalnorm(tmp)
  end
  @pack integrator = t,dt,u
end
