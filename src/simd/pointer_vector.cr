require "./vector"

@[Primitive(:PointerVectorType)]
struct SIMD::PointerVector(T, N)
  include Vector(T, N)
end
