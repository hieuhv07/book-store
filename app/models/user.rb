# frozen_string_literal: true

class User < ApplicationRecord
  enum role: { guest: 0, admin: 1 }
  enum online: { offline: 0, online: 1 }

  has_one :guest_room, class_name: "Room", foreign_key: "guest_id"
  has_many :room_messages
  has_many :assigned_rooms, class_name: "Room", foreign_key: "assignee_id"
  has_many :orders, dependent: :destroy

  validates :fullname, presence: true

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  def re_assign_room
    return if online? || (Time.now - updated_at < Settings.reassign_time_minute.minutes)

    assigned_rooms.each do |room|
      User.select_assignee.assigned_rooms << room
      RoomBroadcastJob.perform_later(room)
    end
  end

  def closed_or_reassigned_room
    if guest? && guest_room.present?
      guest_room.closed!
    elsif admin? && assigned_rooms.present?
      delay(run_at: Settings.reassign_time_minute.minutes.from_now).re_assign_room
    end
  end

  class << self
    def select_assignee
      admins = admin.online.present? ? admin.online : admin.offline
      admins.select("users.*, COUNT(rooms.id) rooms").left_joins(:assigned_rooms).group(:id).order(:rooms).first
    end
  end
end
