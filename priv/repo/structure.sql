--
-- PostgreSQL database dump
--

\restrict uqSFcPhqJltmFoYdSlRrH9bqCA6blcTTOHzgVMVsxSNGF2JRgVWEYBXbRvq67TY

-- Dumped from database version 15.17
-- Dumped by pg_dump version 16.13 (Ubuntu 16.13-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: difficulty_level; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.difficulty_level AS ENUM (
    'easy',
    'medium',
    'hard'
);


--
-- Name: guardian_relationship_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.guardian_relationship_type AS ENUM (
    'parent',
    'teacher'
);


--
-- Name: guardian_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.guardian_status AS ENUM (
    'pending',
    'active',
    'revoked'
);


--
-- Name: ocr_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.ocr_status AS ENUM (
    'pending',
    'processing',
    'completed',
    'failed'
);


--
-- Name: question_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.question_type AS ENUM (
    'multiple_choice',
    'short_answer',
    'free_response',
    'true_false'
);


--
-- Name: user_role_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role_type AS ENUM (
    'student',
    'parent',
    'teacher'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: chapters; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chapters (
    id uuid NOT NULL,
    course_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: countries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.countries (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(255) NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    subject character varying(255) NOT NULL,
    grade character varying(255) NOT NULL,
    school_id uuid,
    description text,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_by_id uuid,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: districts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.districts (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    state_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: hobbies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hobbies (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    category character varying(255) NOT NULL,
    region_relevance jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: ocr_pages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ocr_pages (
    id uuid NOT NULL,
    material_id uuid NOT NULL,
    page_number integer NOT NULL,
    extracted_text text,
    bounding_boxes jsonb,
    images jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: question_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.question_attempts (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    question_id uuid NOT NULL,
    answer_given text NOT NULL,
    is_correct boolean NOT NULL,
    time_taken_seconds integer,
    difficulty_at_attempt character varying(255),
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questions (
    id uuid NOT NULL,
    content text NOT NULL,
    answer text NOT NULL,
    question_type public.question_type NOT NULL,
    options jsonb,
    chapter_id uuid,
    section_id uuid,
    school_id uuid,
    course_id uuid NOT NULL,
    source_url character varying(255),
    source_page integer,
    is_generated boolean DEFAULT false NOT NULL,
    hobby_context character varying(255),
    difficulty public.difficulty_level NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: readiness_scores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.readiness_scores (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    test_schedule_id uuid NOT NULL,
    chapter_scores jsonb NOT NULL,
    topic_scores jsonb NOT NULL,
    aggregate_score double precision NOT NULL,
    calculated_at timestamp(0) without time zone NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: schools; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schools (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    district_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sections (
    id uuid NOT NULL,
    chapter_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    "position" integer NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: states; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.states (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    code character varying(255),
    country_id uuid NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: student_guardians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_guardians (
    id uuid NOT NULL,
    guardian_id uuid NOT NULL,
    student_id uuid NOT NULL,
    relationship_type public.guardian_relationship_type NOT NULL,
    status public.guardian_status DEFAULT 'pending'::public.guardian_status NOT NULL,
    class_name character varying(255),
    invited_at timestamp(0) without time zone NOT NULL,
    accepted_at timestamp(0) without time zone,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: student_hobbies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.student_hobbies (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    hobby_id uuid NOT NULL,
    specific_interests jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: study_guides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.study_guides (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    test_schedule_id uuid,
    content jsonb NOT NULL,
    generated_at timestamp(0) without time zone NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: test_format_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_format_templates (
    id uuid NOT NULL,
    name character varying(255) NOT NULL,
    course_id uuid,
    structure jsonb NOT NULL,
    created_by_id uuid,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: test_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_schedules (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    course_id uuid NOT NULL,
    name character varying(255) NOT NULL,
    test_date date NOT NULL,
    scope jsonb NOT NULL,
    format_template_id uuid,
    notifications_enabled boolean DEFAULT true NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: uploaded_materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.uploaded_materials (
    id uuid NOT NULL,
    user_role_id uuid NOT NULL,
    course_id uuid NOT NULL,
    file_name character varying(255) NOT NULL,
    file_path character varying(255) NOT NULL,
    file_type character varying(255) NOT NULL,
    file_size integer NOT NULL,
    ocr_status public.ocr_status DEFAULT 'pending'::public.ocr_status NOT NULL,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    id uuid NOT NULL,
    interactor_user_id character varying(255) NOT NULL,
    role public.user_role_type NOT NULL,
    email character varying(255),
    display_name character varying(255),
    school_id uuid,
    grade character varying(255),
    metadata jsonb DEFAULT '{}'::jsonb,
    inserted_at timestamp(0) without time zone NOT NULL,
    updated_at timestamp(0) without time zone NOT NULL
);


--
-- Name: chapters chapters_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT chapters_pkey PRIMARY KEY (id);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (id);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: districts districts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_pkey PRIMARY KEY (id);


--
-- Name: hobbies hobbies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hobbies
    ADD CONSTRAINT hobbies_pkey PRIMARY KEY (id);


--
-- Name: ocr_pages ocr_pages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_pages
    ADD CONSTRAINT ocr_pages_pkey PRIMARY KEY (id);


--
-- Name: question_attempts question_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.question_attempts
    ADD CONSTRAINT question_attempts_pkey PRIMARY KEY (id);


--
-- Name: questions questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_pkey PRIMARY KEY (id);


--
-- Name: readiness_scores readiness_scores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.readiness_scores
    ADD CONSTRAINT readiness_scores_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: schools schools_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_pkey PRIMARY KEY (id);


--
-- Name: sections sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_pkey PRIMARY KEY (id);


--
-- Name: states states_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_pkey PRIMARY KEY (id);


--
-- Name: student_guardians student_guardians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_pkey PRIMARY KEY (id);


--
-- Name: student_hobbies student_hobbies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_hobbies
    ADD CONSTRAINT student_hobbies_pkey PRIMARY KEY (id);


--
-- Name: study_guides study_guides_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_guides
    ADD CONSTRAINT study_guides_pkey PRIMARY KEY (id);


--
-- Name: test_format_templates test_format_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_format_templates
    ADD CONSTRAINT test_format_templates_pkey PRIMARY KEY (id);


--
-- Name: test_schedules test_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_schedules
    ADD CONSTRAINT test_schedules_pkey PRIMARY KEY (id);


--
-- Name: uploaded_materials uploaded_materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uploaded_materials
    ADD CONSTRAINT uploaded_materials_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (id);


--
-- Name: chapters_course_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chapters_course_id_index ON public.chapters USING btree (course_id);


--
-- Name: chapters_course_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX chapters_course_id_position_index ON public.chapters USING btree (course_id, "position");


--
-- Name: countries_code_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX countries_code_index ON public.countries USING btree (code);


--
-- Name: courses_created_by_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX courses_created_by_id_index ON public.courses USING btree (created_by_id);


--
-- Name: courses_school_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX courses_school_id_index ON public.courses USING btree (school_id);


--
-- Name: courses_subject_grade_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX courses_subject_grade_index ON public.courses USING btree (subject, grade);


--
-- Name: districts_state_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX districts_state_id_index ON public.districts USING btree (state_id);


--
-- Name: hobbies_name_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX hobbies_name_index ON public.hobbies USING btree (name);


--
-- Name: ocr_pages_material_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocr_pages_material_id_index ON public.ocr_pages USING btree (material_id);


--
-- Name: ocr_pages_material_id_page_number_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ocr_pages_material_id_page_number_index ON public.ocr_pages USING btree (material_id, page_number);


--
-- Name: question_attempts_question_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX question_attempts_question_id_index ON public.question_attempts USING btree (question_id);


--
-- Name: question_attempts_user_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX question_attempts_user_role_id_index ON public.question_attempts USING btree (user_role_id);


--
-- Name: question_attempts_user_role_id_question_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX question_attempts_user_role_id_question_id_index ON public.question_attempts USING btree (user_role_id, question_id);


--
-- Name: questions_chapter_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_chapter_id_index ON public.questions USING btree (chapter_id);


--
-- Name: questions_course_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_course_id_index ON public.questions USING btree (course_id);


--
-- Name: questions_difficulty_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_difficulty_index ON public.questions USING btree (difficulty);


--
-- Name: questions_question_type_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_question_type_index ON public.questions USING btree (question_type);


--
-- Name: questions_school_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_school_id_index ON public.questions USING btree (school_id);


--
-- Name: questions_section_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX questions_section_id_index ON public.questions USING btree (section_id);


--
-- Name: readiness_scores_test_schedule_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX readiness_scores_test_schedule_id_index ON public.readiness_scores USING btree (test_schedule_id);


--
-- Name: readiness_scores_user_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX readiness_scores_user_role_id_index ON public.readiness_scores USING btree (user_role_id);


--
-- Name: readiness_scores_user_role_id_test_schedule_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX readiness_scores_user_role_id_test_schedule_id_index ON public.readiness_scores USING btree (user_role_id, test_schedule_id);


--
-- Name: schools_district_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schools_district_id_index ON public.schools USING btree (district_id);


--
-- Name: sections_chapter_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sections_chapter_id_index ON public.sections USING btree (chapter_id);


--
-- Name: sections_chapter_id_position_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sections_chapter_id_position_index ON public.sections USING btree (chapter_id, "position");


--
-- Name: states_country_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX states_country_id_index ON public.states USING btree (country_id);


--
-- Name: student_guardians_guardian_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_guardians_guardian_id_index ON public.student_guardians USING btree (guardian_id);


--
-- Name: student_guardians_guardian_id_student_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX student_guardians_guardian_id_student_id_index ON public.student_guardians USING btree (guardian_id, student_id);


--
-- Name: student_guardians_student_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_guardians_student_id_index ON public.student_guardians USING btree (student_id);


--
-- Name: student_hobbies_hobby_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX student_hobbies_hobby_id_index ON public.student_hobbies USING btree (hobby_id);


--
-- Name: student_hobbies_user_role_id_hobby_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX student_hobbies_user_role_id_hobby_id_index ON public.student_hobbies USING btree (user_role_id, hobby_id);


--
-- Name: study_guides_test_schedule_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX study_guides_test_schedule_id_index ON public.study_guides USING btree (test_schedule_id);


--
-- Name: study_guides_user_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX study_guides_user_role_id_index ON public.study_guides USING btree (user_role_id);


--
-- Name: test_format_templates_course_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_format_templates_course_id_index ON public.test_format_templates USING btree (course_id);


--
-- Name: test_format_templates_created_by_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_format_templates_created_by_id_index ON public.test_format_templates USING btree (created_by_id);


--
-- Name: test_schedules_course_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_schedules_course_id_index ON public.test_schedules USING btree (course_id);


--
-- Name: test_schedules_format_template_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_schedules_format_template_id_index ON public.test_schedules USING btree (format_template_id);


--
-- Name: test_schedules_test_date_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_schedules_test_date_index ON public.test_schedules USING btree (test_date);


--
-- Name: test_schedules_user_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX test_schedules_user_role_id_index ON public.test_schedules USING btree (user_role_id);


--
-- Name: uploaded_materials_course_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX uploaded_materials_course_id_index ON public.uploaded_materials USING btree (course_id);


--
-- Name: uploaded_materials_ocr_status_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX uploaded_materials_ocr_status_index ON public.uploaded_materials USING btree (ocr_status);


--
-- Name: uploaded_materials_user_role_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX uploaded_materials_user_role_id_index ON public.uploaded_materials USING btree (user_role_id);


--
-- Name: user_roles_interactor_user_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX user_roles_interactor_user_id_index ON public.user_roles USING btree (interactor_user_id);


--
-- Name: user_roles_role_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_roles_role_index ON public.user_roles USING btree (role);


--
-- Name: user_roles_school_id_index; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX user_roles_school_id_index ON public.user_roles USING btree (school_id);


--
-- Name: chapters chapters_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chapters
    ADD CONSTRAINT chapters_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: courses courses_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.user_roles(id) ON DELETE SET NULL;


--
-- Name: courses courses_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id) ON DELETE SET NULL;


--
-- Name: districts districts_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.districts
    ADD CONSTRAINT districts_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.states(id) ON DELETE RESTRICT;


--
-- Name: ocr_pages ocr_pages_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ocr_pages
    ADD CONSTRAINT ocr_pages_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.uploaded_materials(id) ON DELETE CASCADE;


--
-- Name: question_attempts question_attempts_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.question_attempts
    ADD CONSTRAINT question_attempts_question_id_fkey FOREIGN KEY (question_id) REFERENCES public.questions(id) ON DELETE CASCADE;


--
-- Name: question_attempts question_attempts_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.question_attempts
    ADD CONSTRAINT question_attempts_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: questions questions_chapter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) ON DELETE SET NULL;


--
-- Name: questions questions_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: questions questions_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id) ON DELETE SET NULL;


--
-- Name: questions questions_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id) ON DELETE SET NULL;


--
-- Name: readiness_scores readiness_scores_test_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.readiness_scores
    ADD CONSTRAINT readiness_scores_test_schedule_id_fkey FOREIGN KEY (test_schedule_id) REFERENCES public.test_schedules(id) ON DELETE CASCADE;


--
-- Name: readiness_scores readiness_scores_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.readiness_scores
    ADD CONSTRAINT readiness_scores_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: schools schools_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schools
    ADD CONSTRAINT schools_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.districts(id) ON DELETE RESTRICT;


--
-- Name: sections sections_chapter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sections
    ADD CONSTRAINT sections_chapter_id_fkey FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) ON DELETE CASCADE;


--
-- Name: states states_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(id) ON DELETE RESTRICT;


--
-- Name: student_guardians student_guardians_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: student_guardians student_guardians_student_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_guardians
    ADD CONSTRAINT student_guardians_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: student_hobbies student_hobbies_hobby_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_hobbies
    ADD CONSTRAINT student_hobbies_hobby_id_fkey FOREIGN KEY (hobby_id) REFERENCES public.hobbies(id) ON DELETE CASCADE;


--
-- Name: student_hobbies student_hobbies_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.student_hobbies
    ADD CONSTRAINT student_hobbies_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: study_guides study_guides_test_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_guides
    ADD CONSTRAINT study_guides_test_schedule_id_fkey FOREIGN KEY (test_schedule_id) REFERENCES public.test_schedules(id) ON DELETE SET NULL;


--
-- Name: study_guides study_guides_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.study_guides
    ADD CONSTRAINT study_guides_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: test_format_templates test_format_templates_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_format_templates
    ADD CONSTRAINT test_format_templates_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE SET NULL;


--
-- Name: test_format_templates test_format_templates_created_by_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_format_templates
    ADD CONSTRAINT test_format_templates_created_by_id_fkey FOREIGN KEY (created_by_id) REFERENCES public.user_roles(id) ON DELETE SET NULL;


--
-- Name: test_schedules test_schedules_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_schedules
    ADD CONSTRAINT test_schedules_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: test_schedules test_schedules_format_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_schedules
    ADD CONSTRAINT test_schedules_format_template_id_fkey FOREIGN KEY (format_template_id) REFERENCES public.test_format_templates(id) ON DELETE SET NULL;


--
-- Name: test_schedules test_schedules_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.test_schedules
    ADD CONSTRAINT test_schedules_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: uploaded_materials uploaded_materials_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uploaded_materials
    ADD CONSTRAINT uploaded_materials_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: uploaded_materials uploaded_materials_user_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uploaded_materials
    ADD CONSTRAINT uploaded_materials_user_role_id_fkey FOREIGN KEY (user_role_id) REFERENCES public.user_roles(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_school_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id) ON DELETE SET NULL;


--
-- PostgreSQL database dump complete
--

\unrestrict uqSFcPhqJltmFoYdSlRrH9bqCA6blcTTOHzgVMVsxSNGF2JRgVWEYBXbRvq67TY

INSERT INTO public."schema_migrations" (version) VALUES (20260418045439);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045449);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045450);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045451);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045452);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045453);
INSERT INTO public."schema_migrations" (version) VALUES (20260418045454);
