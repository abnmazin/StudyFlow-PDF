-- ================================================================
-- Supabase Setup Script: StudyFlow Multi-Tenant University Storage
-- Run this in your Supabase SQL Editor (Dashboard > SQL Editor)
-- ================================================================

-- 1. Create the university-pdfs bucket (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'university-pdfs',
  'university-pdfs',
  true,  -- Public bucket; getPublicUrl() works without auth
  52428800,  -- 50 MB file size limit
  ARRAY['application/pdf']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- ================================================================
-- ROW LEVEL SECURITY POLICIES
-- ================================================================

-- 2. Helper function: Get the user's universityId from the public.users table
CREATE OR REPLACE FUNCTION storage.get_user_university_id()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  uni_id TEXT;
BEGIN
  SELECT "universityId" INTO uni_id
  FROM public.users
  WHERE uid = auth.uid();
  RETURN uni_id;
END;
$$;

-- 3. Helper function: Get the user's role from the public.users table
CREATE OR REPLACE FUNCTION storage.get_user_role()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role INTO user_role
  FROM public.users
  WHERE uid = auth.uid();
  RETURN user_role;
END;
$$;

-- ================================================================
-- POLICY: SELECT (Download)
-- Allow any authenticated member of the university to download files
-- from their university's folder path
-- ================================================================
CREATE POLICY "University members can download their university's PDFs"
ON storage.objects
FOR SELECT
USING (
  bucket_id = 'university-pdfs'
  AND auth.role() = 'authenticated'
  AND storage.get_user_university_id() IS NOT NULL
  -- Path format: {universityId}/folders/{folderId}/{filename}
  -- We extract the first path segment and compare it to the user's universityId
  AND SPLIT_PART(name, '/', 1) = storage.get_user_university_id()
);

-- ================================================================
-- POLICY: INSERT (Upload)
-- Only admins can upload files to their own university's path
-- ================================================================
CREATE POLICY "Admins can upload PDFs to their university"
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'university-pdfs'
  AND auth.role() = 'authenticated'
  AND storage.get_user_university_id() IS NOT NULL
  AND storage.get_user_role() = 'admin'
  -- First path segment must match the admin's university
  AND SPLIT_PART(name, '/', 1) = storage.get_user_university_id()
);

-- ================================================================
-- POLICY: DELETE
-- Only admins can delete files from their own university's path
-- ================================================================
CREATE POLICY "Admins can delete PDFs from their university"
ON storage.objects
FOR DELETE
USING (
  bucket_id = 'university-pdfs'
  AND auth.role() = 'authenticated'
  AND storage.get_user_university_id() IS NOT NULL
  AND storage.get_user_role() = 'admin'
  -- First path segment must match the admin's university
  AND SPLIT_PART(name, '/', 1) = storage.get_user_university_id()
);

-- ================================================================
-- POLICY: UPDATE
-- Only admins can update (e.g., rename) files in their university's path
-- ================================================================
CREATE POLICY "Admins can update PDFs in their university"
ON storage.objects
FOR UPDATE
USING (
  bucket_id = 'university-pdfs'
  AND auth.role() = 'authenticated'
  AND storage.get_user_university_id() IS NOT NULL
  AND storage.get_user_role() = 'admin'
  AND SPLIT_PART(name, '/', 1) = storage.get_user_university_id()
)
WITH CHECK (
  bucket_id = 'university-pdfs'
  AND auth.role() = 'authenticated'
  AND storage.get_user_university_id() IS NOT NULL
  AND storage.get_user_role() = 'admin'
  AND SPLIT_PART(name, '/', 1) = storage.get_user_university_id()
);

-- ================================================================
-- VERIFICATION QUERIES (Run these to confirm setup)
-- ================================================================

-- Check the bucket was created
-- SELECT * FROM storage.buckets WHERE id = 'university-pdfs';

-- List all policies on the bucket
-- SELECT * FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage';