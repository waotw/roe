class CreateMemberRecoveryCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :member_recovery_codes do |t|
      t.references :member, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :consumed_at

      t.timestamps
    end
  end
end
