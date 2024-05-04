require "./vector"

@[Primitive(:IntVectorType)]
struct SIMD::IntVector(T, N)
  include Vector(T, N)

  @[Primitive(:vector_cast)]
  def self.cast(other : IntVector(U, M)) forall U, M
  end

  @[Primitive(:vector_cast)]
  def self.cast(other : FloatVector(U, M)) forall U, M
  end

  @[Primitive(:vector_cast)]
  def self.cast(other : BoolVector(U, M)) forall U, M
  end

  @[Primitive(:vector_shuffle)]
  def unsafe_shuffle(other : self, indices : IntVector(Int32, M)) : IntVector(T, M) forall M
  end
end
