class AddLabMetaToSuppliers < ActiveRecord::Migration[8.1]
  # LAB / RFQ Auto D-3 — WebSupplierFinder가 발견한 신규 공급사를 자동 저장.
  # 운영 데이터(eCount 동기화/사용자 수동 등록)와 구분하기 위한 메타 컬럼.
  def change
    add_column :suppliers, :auto_imported, :boolean, default: false, null: false
    add_column :suppliers, :import_source, :string  # 'web_search' / 'csv_upload' / 'manual' / 'ecount'
    add_column :suppliers, :discovered_for, :string # 검색에 사용된 키워드 (item_keyword)
    add_column :suppliers, :source_url, :string     # 모델이 참조한 출처 URL

    add_index :suppliers, :auto_imported
    add_index :suppliers, :import_source
  end
end
