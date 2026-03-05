class AddSapPortalLinksToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :sap_portal_links, :text
  end
end
