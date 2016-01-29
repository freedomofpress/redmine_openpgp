module MailHandlerPatch

  def self.included(base) # :nodoc:
    base.send(:include, InstanceMethods)
    base.class_eval do
      alias_method_chain :dispatch_to_default, :openpgp_setting
    end
  end

  module InstanceMethods
        def dispatch_to_default_with_openpgp_setting
          act = Setting.plugin_openpgp['activation']
          project = target_project
          if act == 'all' and !$invalid
            dispatch_to_default_without_openpgp_setting
            return true
          elsif act == 'project'
            if !project.try('module_enabled?', 'openpgp')
              dispatch_to_default_without_openpgp_setting
              return true
            elsif project.try('module_enabled?', 'openpgp') and !$invalid
              dispatch_to_default_without_openpgp_setting
              return true
            else
              logger.info "MailHandler: invalid email rejected to project #{project}" if logger
              return false
            end
          elsif act == 'none'
            dispatch_to_default_without_openpgp_setting
            return true
          end
        end
  end
  
end
