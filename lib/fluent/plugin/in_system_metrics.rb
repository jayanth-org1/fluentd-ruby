require 'fluent/plugin/input'
require 'fluent/counter'

module Fluent
  module Plugin
    class SystemMetricsInput < Input
      Fluent::Plugin.register_input('system_metrics', self)

      helpers :timer

      desc 'Tag to attach to the output events'
      config_param :tag, :string, default: 'system.metrics'
      
      desc 'Interval to collect metrics in seconds'
      config_param :interval, :time, default: 60
      
      desc 'Enable CPU metrics collection'
      config_param :cpu_enabled, :bool, default: true
      
      desc 'Enable memory metrics collection'
      config_param :memory_enabled, :bool, default: true
      
      desc 'Enable disk metrics collection'
      config_param :disk_enabled, :bool, default: true
      
      desc 'Paths to monitor for disk metrics'
      config_param :disk_paths, :array, default: ['/']

      def configure(conf)
        super
        @counters = {}
      end

      def start
        super
        timer_execute(:system_metrics_timer, @interval, &method(:collect_metrics))
      end

      def collect_metrics
        time = Fluent::EventTime.now
        metrics = {}
        
        if @cpu_enabled
          metrics.merge!(collect_cpu_metrics)
        end
        
        if @memory_enabled
          metrics.merge!(collect_memory_metrics)
        end
        
        if @disk_enabled
          metrics.merge!(collect_disk_metrics)
        end
        
        router.emit(@tag, time, metrics)
      end

      private

      def collect_cpu_metrics
        metrics = {}
        begin
          if File.exist?('/proc/stat')
            # Linux CPU metrics
            cpu_stats = File.read('/proc/stat').lines.first
            user, nice, system, idle, iowait, irq, softirq = cpu_stats.split(/\s+/)[1..7].map(&:to_i)
            total = user + nice + system + idle + iowait + irq + softirq
            
            # Store previous values for delta calculation
            prev_total = @counters[:cpu_total] || total
            prev_idle = @counters[:cpu_idle] || idle
            
            # Calculate deltas
            total_delta = total - prev_total
            idle_delta = idle - prev_idle
            
            # Update counters
            @counters[:cpu_total] = total
            @counters[:cpu_idle] = idle
            
            # Calculate usage percentage if we have previous values
            if total_delta > 0
              metrics['cpu.usage_percent'] = 100.0 * (total_delta - idle_delta) / total_delta
            end
          end
        rescue => e
          log.error "Failed to collect CPU metrics", error: e
        end
        metrics
      end

      def collect_memory_metrics
        metrics = {}
        begin
          if File.exist?('/proc/meminfo')
            # Linux memory metrics
            mem_info = File.read('/proc/meminfo')
            total = mem_info.match(/MemTotal:\s+(\d+)/)[1].to_i * 1024
            free = mem_info.match(/MemFree:\s+(\d+)/)[1].to_i * 1024
            available = mem_info.match(/MemAvailable:\s+(\d+)/)[1].to_i * 1024 rescue free
            buffers = mem_info.match(/Buffers:\s+(\d+)/)[1].to_i * 1024
            cached = mem_info.match(/Cached:\s+(\d+)/)[1].to_i * 1024
            
            metrics['memory.total_bytes'] = total
            metrics['memory.free_bytes'] = free
            metrics['memory.available_bytes'] = available
            metrics['memory.used_bytes'] = total - free - buffers - cached
            metrics['memory.usage_percent'] = 100.0 * (total - available) / total if total > 0
          end
        rescue => e
          log.error "Failed to collect memory metrics", error: e
        end
        metrics
      end

      def collect_disk_metrics
        metrics = {}
        begin
          @disk_paths.each do |path|
            next unless File.exist?(path)
            stat = Sys::Filesystem.stat(path)
            
            # Convert block size to bytes
            total_bytes = stat.blocks * stat.block_size
            free_bytes = stat.blocks_free * stat.block_size
            available_bytes = stat.blocks_available * stat.block_size
            used_bytes = total_bytes - free_bytes
            
            path_key = path == '/' ? 'root' : path.gsub(/[^\w]/, '_')
            metrics["disk.#{path_key}.total_bytes"] = total_bytes
            metrics["disk.#{path_key}.free_bytes"] = free_bytes
            metrics["disk.#{path_key}.available_bytes"] = available_bytes
            metrics["disk.#{path_key}.used_bytes"] = used_bytes
            metrics["disk.#{path_key}.usage_percent"] = 100.0 * used_bytes / total_bytes if total_bytes > 0
          end
        rescue => e
          log.error "Failed to collect disk metrics", error: e
        end
        metrics
      end
    end
  end
end 