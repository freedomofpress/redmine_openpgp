module RedmineOpenpgp
  # true if the plugin is active on the given project
  #
  # if global is true, this will be true for setting=='project' if project is nil
  def self.active_on_project?(project, global: false)
    case Setting.plugin_openpgp["activation"]
    when 'all'
      true
    when 'project'
      project.nil? ? global : project.module_enabled?('openpgp')
    else
      false
    end
  end
end
