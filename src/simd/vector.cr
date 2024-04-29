# Base methods
module SIMD::Vector(T, N)
  module ClassMethods(T, N)
  end

  macro included
    extend ::SIMD::Vector::ClassMethods(T, N)
  end
end
