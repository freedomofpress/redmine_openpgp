module MailHandlerPatch
        def dispatch_to_defaul
          act = Setting.plugin_openpgp['activation']
          project = target_project
          if act == 'all' and !$invalid
            super
            return true
          elsif act == 'project'
            if !project.try('module_enabled?', 'openpgp')
              super
              return true
            elsif project.try('module_enabled?', 'openpgp') and !$invalid
              super
              return true
            else
              logger.info "MailHandler: invalid email rejected to project #{project}" if logger
              return false
            end
          elsif act == 'none'
            super
            return true
          end
        end
end
