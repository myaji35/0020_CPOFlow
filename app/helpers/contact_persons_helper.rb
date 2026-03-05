# frozen_string_literal: true

module ContactPersonsHelper
  # Client/Supplier 구분 없이 수정 경로를 반환
  # _row.html.erb 등에서 is_a?(Client) 분기 제거용
  def edit_contactable_contact_person_path(contactable, contact_person)
    if contactable.is_a?(Client)
      edit_client_contact_person_path(contactable, contact_person)
    else
      edit_supplier_contact_person_path(contactable, contact_person)
    end
  end

  # Client/Supplier 구분 없이 삭제 경로를 반환
  def contactable_contact_person_path(contactable, contact_person)
    if contactable.is_a?(Client)
      client_contact_person_path(contactable, contact_person)
    else
      supplier_contact_person_path(contactable, contact_person)
    end
  end

  # Client/Supplier 라벨 (뱃지용)
  def contactable_type_label(contactable)
    if contactable.is_a?(Client)
      "발주처"
    else
      "거래처"
    end
  end

  # Client → blue, Supplier → purple
  def contactable_badge_class(contactable)
    if contactable.is_a?(Client)
      "bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-400"
    else
      "bg-purple-50 dark:bg-purple-900/20 text-purple-700 dark:text-purple-400"
    end
  end
end
