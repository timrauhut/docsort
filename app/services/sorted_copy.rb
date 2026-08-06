class SortedCopy
  class << self
    def path_for(document)
      return if document.relative_path.blank? || document.user.blank?

      global_path = SafeStoragePath.resolve(
        Rails.application.config.x.sorted_root,
        document.relative_path
      )
      return unless SafeStoragePath.contained?(document.user.sorted_root, global_path)

      global_path
    rescue SafeStoragePath::UnsafePath
      nil
    end

    def remove(document)
      path = path_for(document)
      return false unless path&.file?

      path.delete
      prune_empty_parents(path.parent, Pathname.new(document.user.sorted_root).expand_path)
      true
    end

    private

    def prune_empty_parents(path, stop)
      current = path
      while current != stop && SafeStoragePath.contained?(stop, current)
        break unless current.directory? && current.children.empty?

        current.rmdir
        current = current.parent
      end
    rescue SystemCallError
      nil
    end
  end
end
