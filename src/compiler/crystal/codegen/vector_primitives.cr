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

  private def codegen_convert(from_type : BoolVectorInstanceType, to_type : IntVectorInstanceType, arg, *, checked : Bool)
    builder.sext arg, llvm_type(to_type)
  end

  private def codegen_primitive_vector_extract_element(node, target_def, call_args)
    vector = call_args[0]
    index = call_args[1]

    builder.extract_element vector, index
  end

  private def codegen_primitive_vector_insert_element(node, target_def, call_args)
    vector = call_args[0]
    index = call_args[1]
    element = call_args[2]

    builder.insert_element vector, element, index
  end

  private def codegen_primitive_vector_unaligned_load(node, target_def, call_args)
    target_type = node.type
    pointer = call_args[1]

    load = builder.load(llvm_type(target_type), pointer)
    load.alignment = 1
    load
  end

  private def codegen_primitive_vector_unaligned_store(node, target_def, call_args)
    vector = call_args[0]
    pointer = call_args[1]

    store = builder.store(vector, pointer)
    store.alignment = 1
    store
  end

  private def codegen_primitive_vector_cast(node, target_def, call_args)
    target_type = node.type
    vector = call_args[1]

    builder.bit_cast vector, llvm_type(target_type)
  end

  private def codegen_primitive_vector_shuffle(node, target_def, call_args)
    vector1 = call_args[0]
    vector2 = call_args[1]
    indices = call_args[2]

    builder.shuffle_vector vector1, vector2, indices
  end

  private def codegen_primitive_vector_zip(node, target_def, call_args)
    vector_type = target_def.owner
    p1 = call_args[0]
    p2 = call_args[1]
    llvm_type = p1.type

    case {vector_type, target_def.name}
    when {FloatVectorInstanceType, "equals?"}
      builder.fcmp(LLVM::RealPredicate::OEQ, p1, p2)
    when {_, "equals?"}
      builder.icmp(LLVM::IntPredicate::EQ, p1, p2)
    when {IntVectorInstanceType, "greater_than?"}
      builder.icmp(vector_type.signed? ? LLVM::IntPredicate::SGT : LLVM::IntPredicate::UGT, p1, p2)
    when {IntVectorInstanceType, "&+"}
      builder.add(p1, p2)
    when {IntVectorInstanceType, "sat_sub"}
      func = vector_type.signed? ? vector_zip_ssub_sat_fun(llvm_type) : vector_zip_usub_sat_fun(llvm_type)
      call func, call_args
    when {IntVectorInstanceType, "&"}
      builder.and(p1, p2)
    when {IntVectorInstanceType, "|"}
      builder.or(p1, p2)
    else
      raise "BUG: unsupported vector zip primitive '#{Call.full_name(target_def.owner, target_def.name)}'"
    end
  end

  private def codegen_primitive_vector_reduce(node, target_def, call_args)
    vector_type = target_def.owner
    llvm_type = call_args[0].type

    case {vector_type, target_def.name}
    when {BoolVectorInstanceType, "all?"}
      call vector_reduce_and_fun(llvm_type), call_args
    else
      raise "BUG: unsupported vector reduce primitive '#{Call.full_name(target_def.owner, target_def.name)}'"
    end
  end
end
