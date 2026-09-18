export type UserRole =
  | "reader"
  | "affiliate"
  | "writer"
  | "advertiser"
  | "admin";

export type Currency =
  | "NGN"
  | "USD"
  | "GBP"
  | "GHS"
  | "KES";

export type StoryStatus =
  | "draft"
  | "pending_review"
  | "published"
  | "rejected"
  | "archived";

export interface Profile {
  id: string;
  real_name: string;
  nickname: string;
  phone: string;
  country: string;
  role: UserRole;
  phone_verified: boolean;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface Story {
  id: string;
  writer_id: string;
  title: string;
  description: string | null;
  genre: string;
  country: string | null;
  cover_url: string | null;
  price_ngn: number;
  price_usd: number;
  price_gbp: number;
  full_story_price_ngn: number;
  full_story_price_usd: number;
  hard_copy_price_ngn: number;
  status: StoryStatus;
  views: number;
  tips: number;
  published_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Chapter {
  id: string;
  story_id: string;
  chapter_number: number;
  title: string;
  content: string;
  price_ngn: number;
  price_usd: number;
  is_free: boolean;
  created_at: string;
}

export interface Wallet {
  id: string;
  user_id: string;
  currency: Currency;
  balance: number;
  pending_balance: number;
  created_at: string;
  updated_at: string;
}
