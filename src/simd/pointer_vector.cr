require "./vector"

@[Primitive(:PointerVectorType)]
struct SIMD::PointerVector(T, N) < Value
  include Vector(T, N)

  @[Primitive(:vector_cast)]
  def self.cast(other : PointerVector(U, M)) forall U, M
  end

  @[Primitive(:vector_shuffle)]
  def unsafe_shuffle(other : self, indices : IntVector(Int32, M)) : BoolVector(T, M) forall M
  end
end
