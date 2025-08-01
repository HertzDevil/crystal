require "../unix/file_descriptor"

# :nodoc:
module Crystal::System::FileDescriptor
  def self.from_stdio(fd)
    # TODO: WASI doesn't offer a way to detect if a 'fd' is a TTY.
    IO::FileDescriptor.new(fd).tap(&.flush_on_newline=(true))
  end

  def self.fcntl(fd, cmd, arg = 0)
    r = LibC.fcntl(fd, cmd, arg)
    raise IO::Error.from_errno("fcntl() failed") if r == -1
    r
  end

  def self.get_blocking(fd : Handle)
    raise NotImplementedError.new("Crystal::System::FileDescriptor.get_blocking")
  end

  def self.set_blocking(fd : Handle, value : Bool)
    raise NotImplementedError.new("Crystal::System::FileDescriptor.set_blocking")
  end

  protected def system_blocking_init(blocking : Bool?)
  end

  private def system_reopen(other : IO::FileDescriptor)
    raise NotImplementedError.new "Crystal::System::FileDescriptor#system_reopen"
  end

  private def system_flock_shared(blocking)
    raise NotImplementedError.new "Crystal::System::File#system_flock_shared"
  end

  private def system_flock_exclusive(blocking)
    raise NotImplementedError.new "Crystal::System::File#system_flock_exclusive"
  end

  private def system_flock_unlock
    raise NotImplementedError.new "Crystal::System::File#system_flock_unlock"
  end

  private def flock(op : LibC::FlockOp, blocking : Bool = true)
    raise NotImplementedError.new "Crystal::System::File#flock"
  end

  private def system_echo(enable : Bool)
    raise NotImplementedError.new "Crystal::System::FileDescriptor#system_echo"
  end

  private def system_echo(enable : Bool, & : ->)
    raise NotImplementedError.new "Crystal::System::FileDescriptor#system_echo"
  end

  private def system_raw(enable : Bool)
    raise NotImplementedError.new "Crystal::System::FileDescriptor#system_raw"
  end

  private def system_raw(enable : Bool, & : ->)
    raise NotImplementedError.new "Crystal::System::FileDescriptor#system_raw"
  end
end
