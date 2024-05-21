module Crystal
  class CodeGenVisitor
    private def vector_reduce_and_fun(vector_type)
      name = "llvm.vector.reduce.and.#{vector_type.intrinsic_type_name}"
      fetch_typed_fun(@llvm_mod, name) do
        LLVM::Type.function([vector_type], vector_type.element_type)
      end
    end
  end
end
