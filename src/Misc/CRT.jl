import Hecke.rem!, Nemo.crt, Nemo.zero, Nemo.iszero, Nemo.isone
export crt_env, crt, crt_inv, crt_init

isone(a::Int) = (a==1)

function zero!(a::fmpz)
  ccall((:fmpz_zero, :libflint), Void, (Ptr{fmpz}, ), &a)
end

function zero(a::PolyElem)
  return zero(parent(a))
end

function rem!(a::fmpz, b::fmpz, c::fmpz)
  ccall((:fmpz_mod, :libflint), Void, (Ptr{fmpz}, Ptr{fmpz}, Ptr{fmpz}), &a, &b, &c)
end

function rem!(a::fmpz_mod_poly, b::fmpz_mod_poly, c::fmpz_mod_poly)
  ccall((:fmpz_mod_poly_rem, :libflint), Void, (Ptr{fmpz_mod_poly}, Ptr{fmpz_mod_poly}, Ptr{fmpz_mod_poly}), &a, &b, &c)
end

type crt_env{T}
  pr::Array{T, 1}
  id::Array{T, 1}
  tmp::Array{T, 1}
  t1::T
  t2::T
  n::Int
  function crt_env(p::Array{T, 1})
    pr = copy(p)
    id = Array{T, 1}()
    i = 1
    while 2*i <= length(pr)
      a = pr[2*i-1]
      b = pr[2*i]
      if false
        g, u, v = gcdx(a, b)
        @assert isone(g)
        push!(id, v*b , u*a )
      else
        # we have 1 = g = u*a + v*b, so v*b = 1-u*a - which saves one mult.
        u = invmod(a, b)
#        @assert  (a*u) % b == 1
        u *= a
        push!(id, 1-u, u)
      end
      push!(pr, a*b)
      i += 1
    end
    r = new()
    r.pr = pr
    r.id = id

    r.tmp = Array{T, 1}()
    n = length(p)
    for i=1:div(n+1, 2)
      push!(r.tmp, zero(p[1]))
    end
    r.t1 = zero(p[1])
    r.t2 = zero(p[1])

    r.n = n
    return r
  end
end

doc"""
***
   crt_env(p::Array{T, 1}) -> crt_env{T}

> Given coprime moduli in some euclidean ring (FlintZZ, nmod_poly, 
>  fmpz_mod_poly), prepare data for fast application of the chinese
>  remander theorem for those moduli.
"""
function crt_env{T}(p::Array{T, 1})
  return crt_env{T}(p)
end

function show{T}(io::IO, c::crt_env{T})
  print(io, "CRT data for moduli ", c.pr[1:c.n])
end

doc"""
***
   crt{T}(b::Array{T, 1}, a::crt_env{T}) -> T

> Given values in b and the environment prepared by crt_env, return the 
> unique (modulo the product) solution to $x \equiv b_i \bmod p_i$.
"""  
function crt{T}(b::Array{T, 1}, a::crt_env{T})
  res = zero(b[1])
  return crt!(res, b, a)
end

function crt!{T}(res::T, b::Array{T, 1}, a::crt_env{T})
  @assert a.n == length(b)
  bn = div(a.n, 2)
  if isodd(a.n)
    zero!(a.tmp[1])
    add!(a.tmp[1], a.tmp[1], b[end])
    off = 1
  else
    off = 0
  end

  for i=1:bn
    mul!(a.t1, b[2*i-1], a.id[2*i-1])
    mul!(a.t2, b[2*i], a.id[2*i])
    add!(a.tmp[i+off], a.t1, a.t2)
    rem!(a.tmp[i+off], a.tmp[i+off], a.pr[a.n+i])
  end

  if isodd(a.n)
    bn += 1
  end

  id_off = a.n - off
  pr_off = a.n + bn - off
#  println(a.tmp, " id_off=$id_off, pr_off=$pr_off, off=$off, bn=$bn")
  while bn>1
    if isodd(bn)
      off = 1
    else
      off = 0
    end
    bn = div(bn, 2)
    for i=1:bn
      mul!(a.t1, a.tmp[2*i-1], a.id[id_off + 2*i-1])
      mul!(a.t2, a.tmp[2*i], a.id[id_off + 2*i])
      add!(a.tmp[i + off], a.t1, a.t2)
      rem!(a.tmp[i + off], a.tmp[i + off], a.pr[pr_off+i])
    end
    if off == 1
      a.tmp[1], a.tmp[2*bn+1] = a.tmp[2*bn+1], a.tmp[1] 
    end
    id_off += 2*bn
    pr_off += bn
    bn += off
#    println(a.tmp, " id_off=$id_off, pr_off=$pr_off, off=$off, bn=$bn")
  end
  zero!(res)
  add!(res, res, a.tmp[1])
  return res
end

#in .pr we have the products of pairs, ... in the wrong order
# so we traverse this list backwards, while building the remainders...
#.. and then we do it again, efficiently to avoid resorting and re-allocation
#=
function crt_inv{T}(a::T, c::crt_env{T})
  r = Array{T, 1}()
  push!(r, a)
  i = length(c.pr)-1
  j = 1
  while i>1 
    push!(r, r[j] % c.pr[i], r[j] %c.pr[i-1])
    i -= 2
    j += 1
  end
  return reverse(r, length(r)-c.n+1:length(r))
end
=#

function crt_inv!{T}(res::Array{T,1}, a::T, c::crt_env{T})
  for i=1:c.n
    if !isdefined(res, i)
      res[i] = zero(a)
    end
  end

  i = length(c.pr)-1
  r = i
  w = r + c.n - 1

  zero!(res[r % c.n + 1])
  add!(res[r % c.n + 1], res[r % c.n + 1], a)

  while i>1 
    rem!(res[w % c.n + 1], res[r % c.n + 1], c.pr[i])
    rem!(res[(w+c.n - 1) % c.n + 1], res[r % c.n + 1], c.pr[i - 1])
    w += 2*(c.n-1)
    i -= 2
    r += 1*(c.n-1)
  end

  return res
end

function crt_inv{T}(a::T, c::crt_env{T})
  res = Array{T}(c.n)
  return crt_inv!(res, a, c)
end
    
#explains the idea, but is prone to overflow.
# idea: the tree CRT ..
# given moduli p1 .. pn, we first do (p1, p2), (p2, p3), ...
# then ((p1, p2), (p3, p4)), ...
# until done.
# In every step we need the cofactors, the inverse of pi mod pj
# thus we build a parallel array id for the cofactors
# in id[2i-1], id[2i] are the cofactors for pr[2i-1], pr[2i]
# To recombine, we basically loop through the cofactors:
# use id[1], id[2] to combine b[1], b[2] AND append to b
# The product pr[1]*pr[2] was appended to pr, thus we can walk through the 
# growing list till the end
# For the optimized version, we have tmp-array to hold the CRT results
# plus t1, t2 for temporaty products.
function crt(b::Array{Int, 1}, a::crt_env{Int})
  i = a.n+1
  j = 1
  while 2*j <= length(b)
    push!(b, (b[2*j-1]*a.id[2*j-1] + b[2*j]*a.id[2*j]) % a.pr[i])
    j += 1
    i += 1
  end
  return b[end]
end

function crt_test(a::crt_env{fmpz}, b::Int)
  z = [fmpz(0) for x=1:a.n]
  for i=1:b
    b = rand(0:a.pr[end]-1)
    for j=1:a.n
      rem!(z[j], b, a.pr[j])
    end
    if b != crt(z, a)
      println("problem: $b and $z")
    end
    @assert b == crt(z, a)
  end
end


doc"""
***
  crt(r1::GenPoly, m1::GenPoly, r2::GenPoly, m2::GenPoly) -> GenPoly

> Find $r$ such that $r \equiv r_1 \pmod m_1$ and $r \equiv r_2 \pmod m_2$
"""
function crt{T}(r1::GenPoly{T}, m1::GenPoly{T}, r2::GenPoly{T}, m2::GenPoly{T})
  g, u, v = gcdx(m1, m2)
  m = m1*m2
  return (r1*v*m2 + r2*u*m1) % m
end

doc"""
***
  crt_iterative(r::Array{T, 1}, m::Array{T,1}) -> T

> Find $r$ such that $r \equiv r_i \pmod m_i$ for all $i$.
> A plain iteration is performed.
"""
function crt_iterative{T}(r::Array{T, 1}, m::Array{T, 1})
  p = crt(r[1], m[1], r[2], m[2])
  d = m[1] * m[2]
  for i = 3:length(m)
    p = crt(p, d, r[i], m[i])
    d *= m[i]
  end
  return p
end

doc"""
***
  crt_tree(r::Array{T, 1}, m::Array{T,1}) -> T

> Find $r$ such that $r \equiv r_i \pmod m_i$ for all $i$.
> A tree based strategy is used that is asymptotically fast.
"""
function crt_tree{T}(r::Array{T, 1}, m::Array{T, 1})
  if isodd(length(m))
    M = [m[end]]
    V = [r[end]]
  else
    M = Array{T, 1}()
    V = Array{T, 1}()
  end

  for i=1:div(length(m), 2)
    push!(V, crt(r[2*i-1], m[2*i-1], r[2*i], m[2*i]))
    push!(M, m[2*i-1]*m[2*i])
  end
  i = 1
  while 2*i <= length(V)
    push!(V, crt(V[2*i-1], M[2*i-1], V[2*i], M[2*i]))
    push!(M, M[2*i-1] * M[2*i])
    i += 1
  end
#  println("M = $M\nV = $V")
  return V[end]
end

doc"""
***
  crt(r::Array{T, 1}, m::Array{T,1}) -> T

> Find $r$ such that $r \equiv r_i \pmod m_i$ for all $i$.
"""
function crt{T}(r::Array{T, 1}, m::Array{T, 1}) 
  length(r) == length(m) || error("Arrays need to be of same size")
  if length(r) < 5
    return crt_iterative(r, m)
  else
    return crt_tree(r, m)
  end
end

function crt_test_time_all(np::Int, n::Int)
  p = next_prime(fmpz(2)^60)
  m = [p]
  for i=1:np-1
    push!(m, next_prime(m[end]))
  end
  v = [rand(0:x-1) for x = m]
  println("crt_env...")
  @time ce = crt_env(m)
  @time for i=1:n 
    x = crt(v, ce)
  end
  
  println("iterative...")
  @time for i=1:n
    x = crt_iterative(v, m)
  end

  println("tree...")
  @time for i=1:n
    x = crt_tree(v, m)
  end
end  

function _num_setcoeff!(a::nf_elem, n::Int, c::fmpz)
  K = a.parent
  @assert n < degree(K) && n >=0
  ra = pointer_from_objref(a)
  if degree(K) == 1
    ccall((:fmpz_set, :libflint), Void, (Ptr{Void}, Ptr{fmpz}), ra, &c)
    ccall((:fmpq_canonicalise, :libflint), Void, (Ptr{nf_elem}, ), &a)
  elseif degree(K) == 2
     ccall((:fmpz_set, :libflint), Void, (Ptr{Void}, Ptr{fmpz}), ra+n*sizeof(Int), &c)
  else
    ccall((:fmpq_poly_set_coeff_fmpz, :libflint), Void, (Ptr{nf_elem}, Int, Ptr{fmpz}), &a, n, &c)
   # includes canonicalisation and treatment of den.
  end
end

function _num_setcoeff!(a::nf_elem, n::Int, c::UInt)
  K = a.parent
  @assert n < degree(K) && n >=0

  ra = pointer_from_objref(a)
   
  if degree(K) == 1
    ccall((:fmpz_set_ui, :libflint), Void, (Ptr{Void}, Ptr{fmpz}), ra, c)
    ccall((:fmpq_canonicalise, :libflint), Void, (Ptr{nf_elem}, ), &a)
  elseif degree(K) == 2
    ccall((:fmpz_set_ui, :libflint), Void, (Ptr{Void}, UInt), ra+n*sizeof(Int), c)
  else
    ccall((:fmpq_poly_set_coeff_ui, :libflint), Void, (Ptr{nf_elem}, Int, UInt), &a, n, c)
   # includes canonicalisation and treatment of den.
  end
end

function crt_init(K::AnticNumberField, p::fmpz)
  @assert isprime(p)
  Fpx = PolynomialRing(ResidueRing(FlintZZ, p, cached = false), "_x", cached=false)[1]
  fp = Fpx(K.pol)
  lp = factor(fp)
  @assert Set(values(lp.fac)) == Set([1])
  pols = collect(keys(lp.fac))
  ce = crt_env(pols)
  
  function proj(a::nf_elem)
    ap = Fpx(a)
    return crt_inv(ap, ce)
  end
  function lift(a::Array{nmod_poly, 1})
    ap = crt(a, ce)
#    println(ap)
    r = K()
    for i=0:ap.length-1
      u = ccall((:nmod_poly_get_coeff_ui, :libflint), UInt, (Ptr{nmod_poly}, Int), &ap, i)
      _num_setcoeff!(r, i, u)
    end
    return r
  end
  return proj, lift
end

function crt_init(K::AnticNumberField, p::Integer)
  return crt_init(K, fmpz(p))
end


