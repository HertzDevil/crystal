# Base methods
module SIMD::Vector(T, N)
  module ClassMethods(T, N)
    @[Primitive(:vector_literal)]
    def literal(*values : _)
    end

    @[Primitive(:vector_unaligned_load)]
    def unaligned_load(pointer : self*)
    end
  end

  macro included
    extend ::SIMD::Vector::ClassMethods(T, N)
  end

  @[Primitive(:vector_extract_element)]
  def unsafe_fetch(index : Int) : T
  end

  @[Primitive(:vector_insert_element)]
  def unsafe_copy_with(index : Int, value : T) : self
  end

  @[Primitive(:vector_unaligned_store)]
  def unaligned_store(pointer : self*) : Nil
  end

  @[Primitive(:vector_zip)]
  def equals?(other : self) : BoolVector(Bool, N)
  end

  # TODO: support all vector arguments, not just ones with the same type
  def ==(other : self) : Bool
    equals?(other).all?
  end

  def size : Int32
    N
  end

  def each_lane(& : T ->) : Nil
    {% for i in 0...N %}
      yield unsafe_fetch({{ i }})
    {% end %}
  end

  def to_s(io : IO) : Nil
    first = true
    each_lane do |lane|
      io << (first ? "<" : ", ")
      first = false
      lane.inspect(io)
    end
    io << '>'
  end

  def hash(hasher)
    hasher = size.hash(hasher)
    each_lane do |lane|
      hasher = lane.hash(hasher)
    end
    hasher
  end
end
