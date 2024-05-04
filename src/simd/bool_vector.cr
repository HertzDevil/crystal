require "./vector"

@[Primitive(:BoolVectorType)]
struct SIMD::BoolVector(T, N)
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
end
