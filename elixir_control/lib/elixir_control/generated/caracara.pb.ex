defmodule Caracara.SendMessageRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:topic, 1, type: :string)
  field(:payload, 2, type: :bytes)
end

defmodule Caracara.SendMessageReply do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:status, 1, type: :string)
end

defmodule Caracara.SubscribeRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:topic, 1, type: :string)
end

defmodule Caracara.Message do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:payload, 1, type: :bytes)
end

defmodule Caracara.ListTopicsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Caracara.ListTopicsReply do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:topics, 1, repeated: true, type: :string)
end

defmodule Caracara.Caracara.Service do
  @moduledoc false

  use GRPC.Service, name: "caracara.Caracara", protoc_gen_elixir_version: "0.15.0"

  rpc(:SendMessage, Caracara.SendMessageRequest, Caracara.SendMessageReply)

  rpc(:Subscribe, Caracara.SubscribeRequest, stream(Caracara.Message))

  rpc(:ListTopics, Caracara.ListTopicsRequest, Caracara.ListTopicsReply)
end

defmodule Caracara.Caracara.Stub do
  @moduledoc false

  use GRPC.Stub, service: Caracara.Caracara.Service

end
