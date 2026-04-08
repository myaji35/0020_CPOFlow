import { Controller } from "@hotwired/stimulus"

// Procurement Ontology M2 — Drawer Flow 탭 Cytoscape 컨트롤러
//
// Data attributes:
//   data-controller="order-flow"
//   data-order-flow-graph-value="<JSON>"
//   data-order-flow-order-id-value="<id>"
// Targets:
//   data-order-flow-target="canvas"
export default class extends Controller {
  static targets = ["canvas"]
  static values  = { graph: Object, orderId: Number }

  connect() {
    if (typeof window.cytoscape === "undefined") {
      // CDN 미로드 — 짧은 재시도 1회 (defer 스크립트가 늦게 로드될 수 있음)
      this._retry = setTimeout(() => this.render(), 300)
      return
    }
    this.render()
  }

  disconnect() {
    if (this._retry) {
      clearTimeout(this._retry)
      this._retry = null
    }
    if (this.cy) {
      try { this.cy.destroy() } catch (_) {}
      this.cy = null
    }
  }

  render() {
    if (typeof window.cytoscape === "undefined") {
      this.canvasTarget.innerHTML = '<div class="p-4 text-sm" style="color:#16325C;">Cytoscape CDN 로드 실패</div>'
      return
    }
    if (typeof window.cytoscapeDagre !== "undefined") {
      try { window.cytoscape.use(window.cytoscapeDagre) } catch (_) {}
    }

    const data = this.graphValue || { nodes: [], edges: [] }
    if (!data.nodes || data.nodes.length === 0) {
      this.canvasTarget.innerHTML = '<div class="p-4 text-sm" style="color:#16325C;">연결된 거래가 없습니다.</div>'
      return
    }

    const elements = [
      ...data.nodes.map(n => ({
        data: {
          id: n.id,
          label: n.label || n.id,
          type: n.type,
          current: !!n.current,
          virtual: !!n.virtual
        }
      })),
      ...data.edges.map((e, i) => ({
        data: {
          id: `e${i}`,
          source: e.from,
          target: e.to,
          relation: e.relation,
          virtual: !!e.virtual
        }
      }))
    ]

    const useDagre = (typeof window.cytoscapeDagre !== "undefined")
    this.cy = window.cytoscape({
      container: this.canvasTarget,
      elements: elements,
      layout: useDagre
        ? { name: "dagre", rankDir: "TB", padding: 20, nodeSep: 40, rankSep: 60 }
        : { name: "breadthfirst", padding: 20 },
      style: this.cytoscapeStyle()
    })

    this.cy.on("tap", "node", evt => {
      const id = evt.target.data("id")
      const parts = id.split(":")
      const type = parts[0]
      const oid  = parts[1]
      if (type === "Order" && Number(oid) !== this.orderIdValue) {
        const frame = document.getElementById(`drawer-panel-${this.orderIdValue}-flow-frame`)
        if (frame) {
          frame.setAttribute("src", `/orders/${oid}/flow`)
        }
      }
    })
  }

  cytoscapeStyle() {
    return [
      {
        selector: "node",
        style: {
          "background-color": "data(type)",
          "label": "data(label)",
          "color": "#16325C",
          "font-size": "10px",
          "text-valign": "bottom",
          "text-margin-y": 4,
          "width": 36,
          "height": 36,
          "border-width": 1,
          "border-color": "#9CA3AF",
          "background-color": (ele) => this.nodeColor(ele.data("type"))
        }
      },
      {
        selector: "node[?current]",
        style: {
          "border-width": 3,
          "border-color": "#00A1E0",
          "width": 48,
          "height": 48
        }
      },
      {
        selector: "node[?virtual]",
        style: {
          "border-style": "dashed",
          "background-color": "#9CA3AF",
          "opacity": 0.7
        }
      },
      {
        selector: "edge",
        style: {
          "width": 2,
          "line-color": "#1E3A5F",
          "target-arrow-color": "#1E3A5F",
          "target-arrow-shape": "triangle",
          "curve-style": "bezier",
          "label": "data(relation)",
          "font-size": "8px",
          "color": "#16325C",
          "text-background-color": "#ffffff",
          "text-background-opacity": 1,
          "text-background-padding": 2
        }
      },
      {
        selector: "edge[?virtual]",
        style: {
          "line-style": "dashed",
          "line-color": "#9CA3AF",
          "target-arrow-color": "#9CA3AF",
          "width": 1
        }
      }
    ]
  }

  nodeColor(type) {
    const map = {
      "Order":      "#1E3A5F",
      "OrderQuote": "#F4A83A",
      "Client":     "#9CA3AF",
      "Supplier":   "#9CA3AF",
      "Project":    "#9CA3AF"
    }
    return map[type] || "#6B7280"
  }
}
