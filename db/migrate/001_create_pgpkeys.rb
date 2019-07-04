class CreatePgpkeys < ActiveRecord::Migration[5.2]
  def change
    create_table :pgpkeys do |t|
      t.integer :user_id
      t.string :fpr
      t.string :secret
    end
  end
end
