require "./vector"

@[Primitive(:PointerVectorType)]
struct SIMD::PointerVector(T, N)
  include Vector(T, N)

  @[Primitive(:vector_cast)]
  def self.cast(other : PointerVector(U, M)) forall U, M
  end
end
