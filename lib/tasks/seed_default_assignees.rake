# frozen_string_literal: true

# AUDIT-002-FU: Client/Supplier default_assignee 추정 rake
#
# 사용법:
#   DRY_RUN=1 bin/rails seed:default_assignees   # 미리보기 (변경 없음)
#   bin/rails seed:default_assignees              # 실제 실행

namespace :seed do
  desc "Client/Supplier에 default_assignee 추정 (가장 많이 거래한 admin/manager 기준)"
  task default_assignees: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    puts dry_run ? "=== DRY_RUN 모드 (변경 없음) ===" : "=== 실행 모드 ==="
    puts ""

    puts "=== Client default_assignee 추정 ==="
    client_updated = 0
    Client.where(default_assignee_id: nil).find_each do |client|
      # 1순위: assignments.user_id 기준 (admin/manager)
      top_user_id = Assignment
        .joins(:order, :user)
        .where(orders: { client_id: client.id })
        .where(users: { role: %w[admin manager] })
        .group("assignments.user_id")
        .count
        .max_by { |_, v| v }
        &.first

      # 2순위: order.user_id (creator) 기준 (admin/manager)
      top_user_id ||= Order
        .joins(:user)
        .where(client_id: client.id)
        .where(users: { role: %w[admin manager] })
        .group(:user_id)
        .count
        .max_by { |_, v| v }
        &.first

      next unless top_user_id

      user = User.find_by(id: top_user_id)
      next unless user

      if dry_run
        puts "  [DRY] Client##{client.id} '#{client.name}' → #{user.name} (#{user.email})"
      else
        client.update_column(:default_assignee_id, top_user_id)
        puts "  Client##{client.id} '#{client.name}' → #{user.name} (user_id=#{top_user_id})"
        client_updated += 1
      end
    end

    puts ""
    puts "=== Supplier default_assignee 추정 ==="
    supplier_updated = 0
    Supplier.where(default_assignee_id: nil).find_each do |supplier|
      # 1순위: assignments.user_id 기준 (admin/manager)
      top_user_id = Assignment
        .joins(:order, :user)
        .where(orders: { supplier_id: supplier.id })
        .where(users: { role: %w[admin manager] })
        .group("assignments.user_id")
        .count
        .max_by { |_, v| v }
        &.first

      # 2순위: order.user_id (creator) 기준 (admin/manager)
      top_user_id ||= Order
        .joins(:user)
        .where(supplier_id: supplier.id)
        .where(users: { role: %w[admin manager] })
        .group(:user_id)
        .count
        .max_by { |_, v| v }
        &.first

      next unless top_user_id

      user = User.find_by(id: top_user_id)
      next unless user

      if dry_run
        puts "  [DRY] Supplier##{supplier.id} '#{supplier.name}' → #{user.name} (#{user.email})"
      else
        supplier.update_column(:default_assignee_id, top_user_id)
        puts "  Supplier##{supplier.id} '#{supplier.name}' → #{user.name} (user_id=#{top_user_id})"
        supplier_updated += 1
      end
    end

    puts ""
    if dry_run
      puts "DRY_RUN 완료. 실제 실행하려면 DRY_RUN 없이 bin/rails seed:default_assignees"
    else
      puts "완료: Client #{Client.where.not(default_assignee_id: nil).count}/#{Client.count} (이번 업데이트: #{client_updated}건), " \
           "Supplier #{Supplier.where.not(default_assignee_id: nil).count}/#{Supplier.count} (이번 업데이트: #{supplier_updated}건)"
    end
  end
end
