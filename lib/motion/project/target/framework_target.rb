# encoding: utf-8

# Copyright (c) 2012, HipByte SPRL and contributors
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'motion/project/builder'

module Motion; module Project
  class FrameworkTarget
    include Rake::DSL if Object.const_defined?(:Rake) && Rake.const_defined?(:DSL)

    attr_accessor :type

    def initialize(path, type, config, opts)
      @path = path
      @full_path = File.expand_path(path)
      @type = type
      @config = config
      @opts = opts
    end

    def build(platform)
      @platform = platform

      command = if platform == 'iPhoneSimulator'
        "build:simulator"
      else
        if @config.distribution_mode
          "archive:distribution"
        else
          "build:device"
        end
      end

      args = ''
      args << " --trace" if App::VERBOSE

      success = system("cd #{@full_path} && #{environment_variables} rake #{command} #{args}")
      unless success
        App.fail "Target '#{@path}' failed to build"
      end
    end

    def copy_products(platform)
      src_path = framework_path
      dest_path = File.join(@config.app_bundle(platform), 'Frameworks', framework_name)
      FileUtils.mkdir_p(File.join(@config.app_bundle(platform), 'Frameworks'))

      if !File.exist?(dest_path) or File.mtime(src_path) > File.mtime(dest_path)
        App.info 'Copy', src_path
        FileUtils.cp_r(src_path, dest_path)
      end 
    end

    def codesign(platform)
      # Create bundle/ResourceRules.plist.
      resource_rules_plist = File.join(@config.app_bundle(platform), 'Frameworks', framework_name, 'ResourceRules.plist')
      unless File.exist?(resource_rules_plist)
        App.info 'Create', resource_rules_plist
        File.open(resource_rules_plist, 'w') do |io|
          io.write(<<-PLIST)
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>rules</key>
        <dict>
                <key>.*</key>
                <true/>
                <key>Info.plist</key>
                <dict>
                        <key>omit</key>
                        <true/>
                        <key>weight</key>
                        <real>10</real>
                </dict>
                <key>ResourceRules.plist</key>
                <dict>
                        <key>omit</key>
                        <true/>
                        <key>weight</key>
                        <real>100</real>
                </dict>
        </dict>
</dict>
</plist>
PLIST
        end
      end

      codesign_cmd = "CODESIGN_ALLOCATE=\"#{File.join(@config.platform_dir(platform), 'Developer/usr/bin/codesign_allocate')}\" /usr/bin/codesign"
      
      framework_path = File.join(@config.app_bundle(platform), 'Frameworks', framework_name)
      if File.mtime(@config.project_file) > File.mtime(framework_path) \
          or !system("#{codesign_cmd} --verify \"#{framework_path}\" >& /dev/null")
        App.info 'Codesign', framework_path
        sh "#{codesign_cmd} -f -s \"#{@config.codesign_certificate}\" --resource-rules=\"#{resource_rules_plist}\" \"#{framework_path}\""
      end
    end

    def clean
      args = ''
      args << " --trace" if App::VERBOSE
      system("cd #{@full_path} && #{environment_variables} rake clean #{args}")
    end

    def build_dir(config, platform)
      platform + '-' + config.deployment_target + '-' + config.build_mode_name
    end

    def framework_path
      @framework_path ||= begin
        path = File.join(@path, 'build', build_dir(@config, @platform), '*.framework')
        Dir[path].sort_by{ |f| File.mtime(f) }.last
      end
    end

    def framework_name
      File.basename(framework_path)
    end

    # Indicates wether to load the framework at runtime or not
    def load?
      @opts[:load]
    end

    def environment_variables
      [
        "RM_TARGET_SDK_VERSION=\"#{@config.sdk_version}\"",
        "RM_TARGET_DEPLOYMENT_TARGET=\"#{@config.deployment_target}\"",
        "RM_TARGET_XCODE_DIR=\"#{@config.xcode_dir}\"",
        "RM_TARGET_HOST_APP_PATH=\"#{File.expand_path(@config.project_dir)}\"",
        "RM_TARGET_BUILD=\"1\""
      ].join(' ')
    end

  end
end;end