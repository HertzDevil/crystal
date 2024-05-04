class Crystal::CodeGenVisitor
  private def codegen_primitive_vector_literal(node, target_def, call_args)
    llvm_type = llvm_type(node.type)

    if call_args.any?(&.constant?)
      index = 0
      elements = Array(LLVM::Value).new(llvm_type.vector_size)
      undef_element = nil

      call_args.each do |arg|
        if arg.constant?
          elements << arg
        else
          undef_element ||= llvm_type.element_type.undef
          elements << undef_element
        end
        index += 1
      end

      vector = llvm_context.const_vector(elements)
    else
      vector = llvm_type.undef
    end

    call_args.each_with_index do |arg, i|
      unless arg.constant?
        vector = builder.insert_element vector, arg, int32(i)
      end
    end

    vector
  end
end
