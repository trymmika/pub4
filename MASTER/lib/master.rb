# frozen_string_literal: true

module MASTER
  VERSION = "3.0.0"
  CODENAME = "MASTER"
  ROOT = File.expand_path("..", __dir__)  # repo root
  LIB = __dir__                            # lib/ directory (views, templates)
  BOOT_TIME = Time.now
  def self.root = ROOT
end

require_relative "result"
require_relative "db"
require_relative "llm"
require_relative "pledge"
require_relative "pipeline"
require_relative "stages"
