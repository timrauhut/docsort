class AddIssuerToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :issuer, :string
    add_column :documents, :issuer_confidence, :float
    add_index :documents, :issuer
  end
end
