require "./vector"

@[Primitive(:IntVectorType)]
struct SIMD::IntVector(T, N) < Value
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

  @[Primitive(:vector_zip)]
  def &+(other : self) : self
  end

  @[Primitive(:vector_zip)]
  def sat_sub(other : self) : self
  end

  @[Primitive(:vector_zip)]
  def &(other : self) : self
  end

  @[Primitive(:vector_zip)]
  def |(other : self) : self
  end

  @[Primitive(:vector_zip)]
  def greater_than?(other : self) : BoolVector(Bool, N)
  end
end
