require 'fluent/config/element'
require 'fluent/config/types'
require 'fluent/engine'
require 'fluent/plugin'

module Fluent
  class ConfigValidator
    attr_reader :errors, :warnings

    def initialize
      @errors = []
      @warnings = []
    end

    def validate(config_path)
      @errors = []
      @warnings = []
      
      begin
        config_string = File.read(config_path)
        config = Fluent::Config.parse(config_string, config_path, nil, true)
        validate_element(config)
      rescue => e
        @errors << "Failed to parse config file: #{e.message}"
      end
      
      valid?
    end

    def valid?
      @errors.empty?
    end

    private

    def validate_element(element)
      case element.name
      when 'source'
        validate_source(element)
      when 'match'
        validate_match(element)
      when 'filter'
        validate_filter(element)
      when 'label'
        validate_label(element)
      when 'system'
        validate_system(element)
      end

      element.elements.each do |child|
        validate_element(child)
      end
    end

    def validate_source(element)
      type = element['@type']
      if type.nil?
        @errors << "source directive requires @type parameter: #{element}"
        return
      end

      begin
        plugin = Fluent::Plugin.new_input(type)
        validate_plugin_configuration(plugin, element)
      rescue => e
        @errors << "Invalid input plugin '#{type}': #{e.message}"
      end
    end

    def validate_match(element)
      type = element['@type']
      if type.nil?
        @errors << "match directive requires @type parameter: #{element}"
        return
      end

      begin
        plugin = Fluent::Plugin.new_output(type)
        validate_plugin_configuration(plugin, element)
      rescue => e
        @errors << "Invalid output plugin '#{type}': #{e.message}"
      end

      pattern = element.arg
      if pattern.nil? || pattern.empty?
        @errors << "match directive requires pattern argument: #{element}"
      end
    end

    def validate_filter(element)
      type = element['@type']
      if type.nil?
        @errors << "filter directive requires @type parameter: #{element}"
        return
      end

      begin
        plugin = Fluent::Plugin.new_filter(type)
        validate_plugin_configuration(plugin, element)
      rescue => e
        @errors << "Invalid filter plugin '#{type}': #{e.message}"
      end

      pattern = element.arg
      if pattern.nil? || pattern.empty?
        @errors << "filter directive requires pattern argument: #{element}"
      end
    end

    def validate_label(element)
      label_name = element.arg
      if label_name.nil? || label_name.empty?
        @errors << "label directive requires label name argument: #{element}"
      end
    end

    def validate_system(element)
      # Validate system configuration
    end

    def validate_plugin_configuration(plugin, element)
      begin
        conf = element.to_hash
        plugin.configure(conf)
      rescue => e
        @errors << "Plugin configuration error for #{element.name}[@type=#{element['@type']}]: #{e.message}"
      end
    end
  end
end 