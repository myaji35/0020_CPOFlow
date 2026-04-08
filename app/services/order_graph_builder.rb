require "set"

# OrderGraphBuilder — polymorphic OrderLink BFS + 가상 링크 합성
#
# 출력:
#   {
#     nodes: [{ id:, type:, status:, reference_no:, current:, virtual:, label: }],
#     edges: [{ from:, to:, relation:, status:, virtual:, confidence: }]
#   }
class OrderGraphBuilder
  MAX_DEPTH = 3

  def initialize(root, depth: MAX_DEPTH, include_suggested: false)
    @root = root
    @depth = [[depth.to_i, 1].max, MAX_DEPTH].min
    @include_suggested = include_suggested
    @nodes = {}          # id => node hash
    @edges = []          # array of edge hashes
    @explicit_keys = Set.new  # "from|to|relation"
  end

  def call
    add_node(@root, current: true)
    bfs_explicit
    synthesize_reference_no_virtual
    synthesize_fk_virtual
    { nodes: @nodes.values, edges: @edges }
  end

  private

  attr_reader :depth

  def status_filter
    @include_suggested ? %w[confirmed suggested] : %w[confirmed]
  end

  def bfs_explicit
    frontier = [[@root, 0]]
    visited = Set.new(["#{@root.class.name}:#{@root.id}"])
    until frontier.empty?
      node, d = frontier.shift
      next if d >= @depth
      out_links = OrderLink.where(source_type: node.class.name, source_id: node.id, status: status_filter).to_a
      in_links  = OrderLink.where(target_type: node.class.name, target_id: node.id, status: status_filter).to_a
      (out_links + in_links).each do |link|
        other = if link.source_type == node.class.name && link.source_id == node.id
                  link.target
                else
                  link.source
                end
        next if other.nil?
        key = "#{other.class.name}:#{other.id}"
        add_node(other) unless @nodes.key?(key)
        push_explicit_edge(link)
        unless visited.include?(key)
          visited << key
          frontier << [other, d + 1]
        end
      end
    end
  end

  def push_explicit_edge(link)
    from = "#{link.source_type}:#{link.source_id}"
    to   = "#{link.target_type}:#{link.target_id}"
    key = "#{from}|#{to}|#{link.relation}"
    return if @explicit_keys.include?(key)
    @explicit_keys << key
    @edges << {
      from: from, to: to,
      relation: link.relation, status: link.status,
      virtual: false,
      confidence: link.confidence
    }
  end

  def synthesize_reference_no_virtual
    return if @nodes.empty?
    refs = @nodes.values.map { |n| n[:reference_no] }.compact.uniq
    refs.each do |ref|
      same = @nodes.values.select { |n| n[:reference_no] == ref && n[:type] == "Order" }
      next if same.size < 2
      same.combination(2).each do |a, b|
        push_virtual_edge(a[:id], b[:id], "references")
      end
    end
  end

  def synthesize_fk_virtual
    @nodes.values.dup.each do |n|
      next unless n[:type] == "Order"
      order = Order.find_by(id: n[:id].split(":").last)
      next unless order
      [
        [order.client,   "Client",   "requested_by"],
        [order.supplier, "Supplier", "quoted_by"],
        [order.project,  "Project",  "for_project"]
      ].each do |obj, type, relation|
        next unless obj
        vnode_id = "#{type}:#{obj.id}"
        unless @nodes.key?(vnode_id)
          @nodes[vnode_id] = {
            id: vnode_id,
            type: type,
            status: nil,
            reference_no: nil,
            current: false,
            virtual: true,
            label: obj.respond_to?(:name) ? obj.name : "#{type}##{obj.id}"
          }
        end
        push_virtual_edge(n[:id], vnode_id, relation)
      end
    end
  end

  def push_virtual_edge(from, to, relation)
    return if @explicit_keys.include?("#{from}|#{to}|#{relation}")
    return if @edges.any? { |e| e[:from] == from && e[:to] == to && e[:relation] == relation }
    @edges << {
      from: from, to: to,
      relation: relation, status: "virtual",
      virtual: true, confidence: nil
    }
  end

  def add_node(obj, current: false)
    id = "#{obj.class.name}:#{obj.id}"
    @nodes[id] = {
      id: id,
      type: obj.class.name,
      status: obj.respond_to?(:status) ? obj.status : nil,
      reference_no: obj.respond_to?(:reference_no) ? obj.reference_no : nil,
      current: current,
      virtual: false,
      label: node_label(obj)
    }
  end

  def node_label(obj)
    if obj.respond_to?(:title) && obj.title.present?
      obj.title
    elsif obj.respond_to?(:reference_no) && obj.reference_no.present?
      obj.reference_no
    else
      "#{obj.class.name}##{obj.id}"
    end
  end
end
