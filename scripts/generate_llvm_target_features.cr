#! /usr/bin/env crystal
#
# Prints all target-model-feature triples. For example, the triple
# `{"X86", "x86-64-v3", "avx2"}` means that using `--mcpu=x86-64-v3` when
# compiling for the X86 target implies `--mattr=+avx2`.
#
# The first CLI argument should be the LLVM source root directory, such as
# `.../llvm-project/llvm`. Also the `llvm-tblgen` program must be available.

require "json"
require "log"

Log.setup "*", backend: Log::IOBackend.new(STDERR)

def find_llvm_tblgen
  if llvm_tblgen = ENV["LLVM_TBLGEN"]?
    return llvm_tblgen
  end

  llvm_config = ENV["LLVM_CONFIG"]?
  {% unless flag?(:win32) %}
    unless llvm_config
      io = IO::Memory.new
      if Process.run("#{__DIR__}/../src/llvm/ext/find-llvm-config", output: io).success?
        llvm_config = io.to_s.strip
      end
    end
  {% end %}

  if llvm_config
    io = IO::Memory.new
    if Process.run(llvm_config, %w(--bindir), output: io).success?
      return File.join(io.to_s.strip, "llvm-tblgen")
    end
  end

  if llvm_tblgen = Process.find_executable("llvm-tblgen")
    return llvm_tblgen
  end

  raise "Cannot locate llvm-tblgen (try overriding it with $LLVM_TBLGEN)"
end

LLVM_TBLGEN   = find_llvm_tblgen
TARGETS       = %w(X86 AArch64 ARM WebAssembly)
LLVM_SRC_ROOT = ARGV.shift? || abort "Usage: crystal #{File.basename __FILE__} <LLVM source root directory>"

module TableGen
  struct Ref
    include JSON::Serializable

    @[JSON::Field(key: "def")]
    getter def_id : String
  end

  struct SubtargetFeature
    include JSON::Serializable

    @[JSON::Field(key: "!name")]
    getter id : String

    @[JSON::Field(key: "Name")]
    getter name : String

    @[JSON::Field(key: "Implies")]
    getter implies : Array(Ref)
  end

  struct ProcessorModel
    include JSON::Serializable

    @[JSON::Field(key: "!name")]
    getter id : String

    @[JSON::Field(key: "Name")]
    getter name : String

    @[JSON::Field(key: "Features")]
    getter features : Array(Ref)

    @[JSON::Field(key: "TuneFeatures")]
    getter tune_features : Array(Ref)
  end

  struct InstanceOf
    include JSON::Serializable

    @[JSON::Field(key: "SubtargetFeature")]
    getter subtarget_feature : Set(String) = Set(String).new

    @[JSON::Field(key: "ProcessorModel")]
    getter processor_model : Set(String) = Set(String).new

    def initialize
    end
  end
end

def add_implied_features(feature, all_features, added)
  if added.add?(feature)
    feature.implies.each do |imply|
      add_implied_features(all_features[imply.def_id], all_features, added)
    end
  end
end

lookup = [] of {String, String, String}

TARGETS.each do |target|
  instanceof_ids = TableGen::InstanceOf.new
  all_subtarget_features = {} of String => TableGen::SubtargetFeature
  all_processor_models = {} of String => TableGen::ProcessorModel

  args = ["-I", "../../../include", "#{target}.td", "--dump-json"]
  chdir = File.join(LLVM_SRC_ROOT, "lib", "Target", target)
  Log.info { "chdir #{Process.quote(chdir)} && #{Process.quote(LLVM_TBLGEN)} #{Process.quote(args)}" }

  Process.run(LLVM_TBLGEN, args, chdir: chdir) do |process|
    pull = JSON::PullParser.new(process.output)
    pull.read_object do |key|
      if key == "!instanceof"
        # this should be the first key emitted by llvm-tblgen, if not then
        # something must be wrong!
        instanceof_ids = TableGen::InstanceOf.new(pull)
      elsif instanceof_ids.subtarget_feature.includes?(key)
        feature = TableGen::SubtargetFeature.new(pull)
        all_subtarget_features[feature.id] = feature
      elsif instanceof_ids.processor_model.includes?(key)
        model = TableGen::ProcessorModel.new(pull)
        all_processor_models[model.id] = model
      else
        pull.skip
      end
    end
  end

  implied_features = all_subtarget_features.transform_values do |feature|
    set = Set(TableGen::SubtargetFeature).new
    add_implied_features(feature, all_subtarget_features, set)
    set
  end

  all_processor_models.each do |id, model|
    processor_features = Set(TableGen::SubtargetFeature).new
    model.features.each do |feature|
      processor_features.concat(implied_features[feature.def_id])
    end
    model.tune_features.each do |feature|
      processor_features.concat(implied_features[feature.def_id])
    end
    processor_features.each do |feature|
      lookup << {target, model.name, feature.name}
    end
  end
end

lookup.sort!
lookup.each { |v| p v }
