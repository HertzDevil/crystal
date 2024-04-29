require "./vector"

@[Primitive(:BoolVectorType)]
struct SIMD::BoolVector(T, N)
  include Vector(T, N)
end
