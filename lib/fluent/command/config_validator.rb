require 'fluent/command/base'
require 'fluent/config_validator'
require 'optparse'

module Fluent
  module Command
    class ConfigValidator < Fluent::Command::Base
      def initialize
        super
        @options = {
          verbose: false,
          strict: false
        }
      end

      def run(argv = ARGV)
        parse_options!(argv)
        
        if argv.empty?
          puts "Error: No configuration file specified"
          puts @opt_parser.help
          exit 1
        end

        exit_code = 0
        argv.each do |config_path|
          unless File.exist?(config_path)
            puts "Error: Configuration file not found: #{config_path}"
            exit_code = 1
            next
          end

          validator = Fluent::ConfigValidator.new
          valid = validator.validate(config_path)
          
          puts "Validating #{config_path}..."
          
          if validator.errors.any?
            puts "Errors:"
            validator.errors.each do |error|
              puts "  - #{error}"
            end
            exit_code = 1
          end
          
          if @options[:verbose] && validator.warnings.any?
            puts "Warnings:"
            validator.warnings.each do |warning|
              puts "  - #{warning}"
            end
          end
          
          if valid
            puts "Configuration is valid."
          else
            puts "Configuration is invalid."
          end
          puts
        end
        
        exit exit_code
      end

      private

      def parse_options!(argv)
        @opt_parser = OptionParser.new do |opts|
          opts.banner = "Usage: fluent-config-validator [options] CONFIG_FILE1 [CONFIG_FILE2 ...]"
          
          opts.on("-v", "--verbose", "Show warnings in addition to errors") do
            @options[:verbose] = true
          end
          
          opts.on("-s", "--strict", "Enable strict validation mode") do
            @options[:strict] = true
          end
          
          opts.on("-h", "--help", "Show this help message") do
            puts opts
            exit 0
          end
        end
        
        @opt_parser.parse!(argv)
      end
    end
  end
end 