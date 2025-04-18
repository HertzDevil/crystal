struct LLVM::BasicBlock
  def initialize(@unwrap : LibLLVM::BasicBlockRef)
  end

  def self.null
    LLVM::BasicBlock.new(Pointer(::Void).null.as(LibLLVM::BasicBlockRef))
  end

  def instructions
    InstructionCollection.new self
  end

  def delete
    LibLLVM.delete_basic_block self
  end

  def to_unsafe
    @unwrap
  end

  def name
    block_name = LibLLVM.get_basic_block_name(self)
    block_name ? String.new(block_name) : nil
  end

  def parent : Function?
    parent_func = LibLLVM.get_basic_block_parent(self)
    parent_func ? Function.new(parent_func) : nil
  end
end
