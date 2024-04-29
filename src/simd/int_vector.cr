require "./vector"

@[Primitive(:IntVectorType)]
struct SIMD::IntVector(T, N)
  include Vector(T, N)
end
