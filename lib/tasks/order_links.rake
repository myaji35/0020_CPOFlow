# frozen_string_literal: true

# OrderLink 백필 rake task — 기존 OrderQuote, Order.parent_order_id를
# order_links 테이블에 일괄 백필. find_or_create_by로 멱등성 보장.
namespace :order_links do
  desc "기존 데이터를 order_links에 백필 (실행 전 dry_run 권장)"
  task backfill: :environment do
    OrderLinksBackfiller.new(dry_run: false).call
  end

  namespace :backfill do
    desc "백필 dry-run — 생성 예정 건수만 출력 (DB 변경 없음)"
    task dry_run: :environment do
      OrderLinksBackfiller.new(dry_run: true).call
    end
  end
end

# rake task 내부 헬퍼 클래스 (rake 파일 안에 정의)
class OrderLinksBackfiller
  def initialize(dry_run:)
    @dry_run = dry_run
    @stats = { quoted_as: 0, derived_from: 0, skipped: 0 }
  end

  def call
    puts "=" * 60
    puts @dry_run ? "DRY RUN — 실제 생성하지 않음" : "백필 실행 — DB에 INSERT"
    puts "=" * 60

    backfill_quoted_as
    backfill_derived_from
    print_summary
  end

  private

  def backfill_quoted_as
    OrderQuote.find_each do |q|
      attrs = {
        source_type: "Order", source_id: q.order_id,
        target_type: "OrderQuote", target_id: q.id,
        relation: "quoted_as"
      }
      if OrderLink.exists?(attrs)
        @stats[:skipped] += 1
        next
      end
      unless @dry_run
        OrderLink.create!(attrs.merge(
          status: OrderLink::STATUSES.first,
          confidence: 1.0,
          metadata: {
            "source"  => "backfill",
            "trigger" => "OrderQuote_backfill"
          }
        ))
      end
      @stats[:quoted_as] += 1
    end
  end

  def backfill_derived_from
    Order.where.not(parent_order_id: nil).find_each do |o|
      attrs = {
        source_type: "Order", source_id: o.id,
        target_type: "Order", target_id: o.parent_order_id,
        relation: "derived_from"
      }
      if OrderLink.exists?(attrs)
        @stats[:skipped] += 1
        next
      end
      unless @dry_run
        OrderLink.create!(attrs.merge(
          status: OrderLink::STATUSES.first,
          confidence: 1.0,
          metadata: {
            "source"  => "backfill",
            "trigger" => "parent_order_backfill"
          }
        ))
      end
      @stats[:derived_from] += 1
    end
  end

  def print_summary
    puts ""
    puts "결과:"
    puts "  quoted_as    : #{@stats[:quoted_as]}"
    puts "  derived_from : #{@stats[:derived_from]}"
    puts "  skipped (already exists): #{@stats[:skipped]}"
    puts "=" * 60
  end
end
