class SafeStoragePath
  class UnsafePath < ArgumentError; end

  class << self
    def resolve(root, relative)
      root_path = Pathname.new(root.to_s).expand_path.cleanpath
      relative_path = Pathname.new(relative.to_s)
      raise UnsafePath, "absolute paths are not allowed" if relative_path.absolute?

      candidate = root_path.join(relative_path).cleanpath
      raise UnsafePath, "path escapes storage root" unless contained?(root_path, candidate)

      ensure_existing_ancestor_within_root!(root_path, candidate)
      candidate
    end

    def safe_relative?(value)
      raw = value.to_s
      return false if raw.blank? || raw.include?("\0") || raw.include?("\\")

      path = Pathname.new(raw)
      return false if path.absolute?

      segments = raw.split("/")
      segments.none? { |segment| segment.blank? || segment.in?([ ".", ".." ]) }
    end

    def contained?(root, candidate)
      root_path = Pathname.new(root.to_s).expand_path.cleanpath
      candidate_path = Pathname.new(candidate.to_s).expand_path.cleanpath
      relative = candidate_path.relative_path_from(root_path).to_s
      relative != ".." && !relative.start_with?("../")
    rescue ArgumentError
      false
    end

    private

    def ensure_existing_ancestor_within_root!(root, candidate)
      # If the root itself does not exist yet there cannot be a symlink inside it;
      # lexical containment above is sufficient until mkdir_p creates the root.
      return unless root.exist?

      real_root = root.realpath
      ancestor = candidate
      ancestor = ancestor.parent until ancestor.exist? || ancestor == ancestor.parent
      return unless ancestor.exist?
      return if contained?(real_root, ancestor.realpath)

      raise UnsafePath, "path resolves outside storage root"
    end
  end
end
