class Kamal::Commands::Accessory < Kamal::Commands::Base
  attr_reader :accessory_config
  delegate :service_name, :image, :hosts, :port, :files, :directories, :cmd,
           :network_args, :publish_args, :env_args, :volume_args, :label_args, :option_args,
           :secrets_io, :secrets_path, :env_directory, :running_proxy?,
           to: :accessory_config
  delegate :proxy_container_name, to: :config


  def initialize(config, name:)
    super(config)
    @accessory_config = config.accessory(name)
  end

  def run
    docker :run,
      "--name", service_name,
      "--detach",
      "--restart", "unless-stopped",
      *network_args,
      *config.logging_args,
      *publish_args,
      *env_args,
      *volume_args,
      *label_args,
      *option_args,
      image,
      cmd
  end

  def start
    docker :container, :start, service_name
  end

  def stop
    docker :container, :stop, service_name
  end

  def info
    docker :ps, *service_filter
  end

  def deploy(target:)
    proxy_exec :deploy, service_name, *accessory_config.proxy.deploy_command_args(target: target)
  end

  def remove(target:)
    proxy_exec :remove, service_name, *accessory_config.proxy.remove_command_args(target: target)
  end


  def logs(timestamps: true, since: nil, lines: nil, grep: nil, grep_options: nil)
    pipe \
      docker(:logs, service_name, (" --since #{since}" if since), (" --tail #{lines}" if lines), ("--timestamps" if timestamps), "2>&1"),
      ("grep '#{grep}'#{" #{grep_options}" if grep_options}" if grep)
  end

  def follow_logs(timestamps: true, grep: nil, grep_options: nil)
    run_over_ssh \
      pipe \
        docker(:logs, service_name, ("--timestamps" if timestamps), "--tail", "10", "--follow", "2>&1"),
        (%(grep "#{grep}"#{" #{grep_options}" if grep_options}) if grep)
  end


  def execute_in_existing_container(*command, interactive: false)
    docker :exec,
      ("-it" if interactive),
      service_name,
      *command
  end

  def execute_in_new_container(*command, interactive: false)
    docker :run,
      ("-it" if interactive),
      "--rm",
      *network_args,
      *env_args,
      *volume_args,
      image,
      *command
  end

  def execute_in_existing_container_over_ssh(*command)
    run_over_ssh execute_in_existing_container(*command, interactive: true)
  end

  def execute_in_new_container_over_ssh(*command)
    run_over_ssh execute_in_new_container(*command, interactive: true)
  end

  def run_over_ssh(command)
    super command, host: hosts.first
  end


  def ensure_local_file_present(local_file)
    if !local_file.is_a?(StringIO) && !Pathname.new(local_file).exist?
      raise "Missing file: #{local_file}"
    end
  end

  def remove_service_directory
    [ :rm, "-rf", service_name ]
  end

  def remove_container
    docker :container, :prune, "--force", *service_filter
  end

  def remove_image
    docker :image, :rm, "--force", image
  end

  def ensure_env_directory
    make_directory env_directory
  end

  private
    def service_filter
      [ "--filter", "label=service=#{service_name}" ]
    end

    def proxy_exec(*command)
      docker :exec, proxy_container_name, "kamal-proxy", *command
    end
end
