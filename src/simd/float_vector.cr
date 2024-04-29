require "./vector"

@[Primitive(:FloatVectorType)]
struct SIMD::FloatVector(T, N)
  include Vector(T, N)
end
