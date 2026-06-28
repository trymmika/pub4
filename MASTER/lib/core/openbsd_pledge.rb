# frozen_string_literal: true

require_relative '../pledge'

module MASTER
  # OpenBSD pledge/unveil integration.
  #
  # This delegates to the real syscall wrapper in lib/pledge.rb (Fiddle -> libc).
  # It does NOT pretend to apply security it isn't applying: off OpenBSD it is an
  # honest no-op, and on OpenBSD the main-process pledge is opt-in via MASTER_PLEDGE=1
  # until the promise/unveil set has been verified on-target, because an incorrect
  # promise set aborts the process (SIGABRT) the moment it touches an unpledged
  # operation. Child-process sandboxing (the safe place to pledge) lives in
  # Stages::Execute, which already wraps an untrusted subprocess with Pledge.
  class OpenBSDPledge
    # Promise sets. The CLI is interactive (tty-prompt), execs subprocesses, and
    # talks to the network, so a usable profile must include tty/proc/exec/inet/dns.
    PROMISES = {
      minimal:   'stdio',
      read_only: 'stdio rpath tty',
      network:   'stdio rpath wpath cpath inet dns tty',
      full:      'stdio rpath wpath cpath inet dns proc exec tty'
    }.freeze

    # Unveil paths derived from MASTER::ROOT (never hardcoded CI paths).
    def self.unveil_paths
      {
        root: { path: MASTER::ROOT, permissions: 'rwc' },
        tmp:  { path: '/tmp',       permissions: 'rwc' },
        home: { path: ENV['HOME'],  permissions: 'rwc' }
      }.compact
    end

    class << self
      def openbsd? = RUBY_PLATFORM.include?('openbsd')

      # Apply pledge for the given mode. Returns true if actually applied.
      # Raises nothing on non-OpenBSD; surfaces real failures visibly.
      def pledge(mode = :network)
        return false unless openbsd? && Pledge.available?
        unless ENV['MASTER_PLEDGE'] == '1'
          log("pledge not applied (set MASTER_PLEDGE=1 to enable; promise set pending on-target verification)")
          return false
        end
        promises = PROMISES[mode] || mode.to_s
        Pledge.pledge(promises)
        log("pledged: #{promises}")
        true
      rescue Pledge::Error => e
        warn "pledge(2) failed: #{e.message}"
        false
      end

      # Unveil filesystem paths, then implicitly lock by pledging without 'unveil'.
      def unveil(paths = unveil_paths)
        return false unless openbsd? && Pledge.available?
        return false unless ENV['MASTER_PLEDGE'] == '1'
        paths.each_value do |config|
          next unless config[:path]
          Pledge.unveil(config[:path], config[:permissions])
          log("unveiled: #{config[:path]} (#{config[:permissions]})")
        end
        true
      rescue Pledge::Error => e
        warn "unveil(2) failed: #{e.message}"
        false
      end

      # Apply unveil then pledge (order matters: restrict fs before dropping unveil).
      def secure(mode = :network, paths = unveil_paths)
        unveil(paths)
        pledge(mode)
      end

      def status
        {
          platform: RUBY_PLATFORM,
          openbsd: openbsd?,
          syscalls_available: openbsd? && Pledge.available?,
          enabled: ENV['MASTER_PLEDGE'] == '1',
          current_mode: @current_mode || :none
        }
      end

      def cli_profile
        @current_mode = :cli
        secure(:full)
      end

      def server_profile
        @current_mode = :server
        secure(:network)
      end

      def readonly_profile
        @current_mode = :readonly
        secure(:read_only, root: { path: MASTER::ROOT, permissions: 'r' })
      end

      private

      def log(message)
        return unless ENV['DEBUG'] || ENV['SECURITY_LOG']
        puts "[security #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] #{message}"
      end
    end
  end
end
