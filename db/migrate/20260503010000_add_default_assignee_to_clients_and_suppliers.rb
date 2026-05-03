# frozen_string_literal: true

class AddDefaultAssigneeToClientsAndSuppliers < ActiveRecord::Migration[8.1]
  def change
    add_reference :clients, :default_assignee, foreign_key: { to_table: :users }, null: true
    add_reference :suppliers, :default_assignee, foreign_key: { to_table: :users }, null: true
  end
end
