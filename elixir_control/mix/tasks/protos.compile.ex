defmodule Mix.Tasks.Protos.Compile do
  use Mix.Task

  # Need to add protoc: brew install protobuf
  # and protoc-gen-elixir mix escript.install hex protobuf 0.15.0 current version at creation
  # generate the files with:
  # protoc --elixir_out=plugins=grpc:lib/elixir_control/generated -I ../proto ../proto/caracara.proto

  @shortdoc "Compiles protocol buffer and gRPC files"

  def run(_) do
    out_dir = "lib/elixir_control/generated"
    File.mkdir_p!(out_dir)

    proto_dir = "../proto"
    proto_files = Path.wildcard(Path.join(proto_dir, "*.proto"))

    args = [
      "--elixir_out=#{out_dir}",
      "-I",
      proto_dir | proto_files
    ]

    Mix.shell().info("Compiling .proto files ... ")

    case System.cmd("protoc", args) do
      {_result, 0} ->
        Mix.shell().info("Successfully compiled .proto files into #{out_dir}")

      {output, error_code} ->
        Mix.shell().error("Failed to compile .proto files (exit status): #{error_code}")
        Mix.shell().error(output)
        Mix.raise("protoc compilation failed.")
    end
  end
end
