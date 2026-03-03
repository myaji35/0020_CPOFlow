namespace :orders do
  desc "기존 Order의 제목/본문에서 reference_no를 추출하여 채웁니다"
  task backfill_reference_no: :environment do
    scope = Order.where(reference_no: nil)
    total = scope.count
    updated = 0

    puts "대상 Order: #{total}건"

    scope.find_each do |order|
      ref = Gmail::ReferenceNumberExtractor.extract(
        order.original_email_subject.to_s,
        order.original_email_body.to_s
      )
      next if ref.blank?

      order.update_column(:reference_no, ref)
      updated += 1
      print "."
    end

    puts "\n완료: #{updated}/#{total}건 업데이트"
  end
end
