defmodule FunSheep.Courses.KnownTestProfiles do
  @moduledoc """
  Detects well-known standardized tests from a course name and returns a
  pre-built generation profile (prompt_context, validation_rules,
  score_predictor_weights, suggested chapter structure).

  Profiles are derived from official test specifications so that AI-generated
  questions target the correct domains, format, and difficulty distribution
  without requiring the teacher to describe the test manually.
  """

  @type profile :: %{
          display_name: String.t(),
          catalog_test_type: String.t(),
          catalog_subject: String.t(),
          description: String.t(),
          generation_config: map(),
          score_predictor_weights: map(),
          suggested_chapters: [%{name: String.t(), sections: [String.t()]}]
        }

  # Pattern → profile key. Ordered most-specific first.
  @patterns [
    {~r/\bsat\b.*(read|writing|verbal|english|rw)/i, :sat_rw},
    {~r/\bsat\b/i, :sat_math},
    {~r/\bact\b.*english/i, :act_english},
    {~r/\bact\b.*read/i, :act_reading},
    {~r/\bact\b.*sci/i, :act_science},
    {~r/\bact\b/i, :act_math},
    {~r/\bgre\b.*(quant|math)/i, :gre_quant},
    {~r/\bgre\b.*(verbal|read)/i, :gre_verbal},
    {~r/\bgre\b/i, :gre_quant},
    {~r/\bgmat\b.*(quant|math)/i, :gmat_quant},
    {~r/\bgmat\b.*(verbal)/i, :gmat_verbal},
    {~r/\blsat\b.*(logic|reason)/i, :lsat_lr},
    {~r/\blsat\b.*(read)/i, :lsat_rc},
    {~r/\blsat\b/i, :lsat_lr},
    {~r/\bap\b.*bio/i, :ap_biology},
    {~r/\bap\b.*calc.*bc/i, :ap_calc_bc},
    {~r/\bap\b.*calc/i, :ap_calc_ab},
    {~r/\bap\b.*chem/i, :ap_chemistry},
    {~r/\bap\b.*us.hist/i, :ap_us_history},
    {~r/\bap\b.*eng.*lang/i, :ap_english_lang},
    {~r/\bap\b.*phys/i, :ap_physics}
  ]

  @profiles %{
    sat_math: %{
      display_name: "Digital SAT — Math",
      catalog_test_type: "sat",
      catalog_subject: "mathematics",
      description:
        "Complete Digital SAT Math preparation covering all four content domains. Adaptive practice identifies and targets your weak areas across Algebra, Advanced Math, Problem-Solving, and Geometry.",
      generation_config: %{
        "prompt_context" =>
          "Digital SAT Math — adaptive multistage exam, 44 questions across two 22-question modules (35 min each), 70 minutes total, calculator permitted throughout. Questions cover Algebra (35%), Advanced Math (35%), Problem-Solving and Data Analysis (15%), and Geometry and Trigonometry (15%). Most questions are 4-option multiple choice (A–D); approximately 20% are student-produced response with no answer choices.",
        "validation_rules" => %{
          "mcq_option_count" => 4,
          "answer_labels" => ["A", "B", "C", "D"]
        }
      },
      score_predictor_weights: %{
        "algebra" => 0.35,
        "advanced_math" => 0.35,
        "problem_solving_data_analysis" => 0.15,
        "geometry_trigonometry" => 0.15
      },
      suggested_chapters: [
        %{
          name: "Algebra",
          sections: [
            "Linear Equations in One Variable",
            "Linear Equations in Two Variables",
            "Linear Functions and Graphs",
            "Systems of Two Linear Equations",
            "Linear Inequalities",
            "Word Problems: Setting Up Equations"
          ]
        },
        %{
          name: "Advanced Math",
          sections: [
            "Quadratic Equations — Factoring",
            "Quadratic Equations — Completing the Square",
            "Quadratic Functions — Vertex and Axis of Symmetry",
            "Polynomial Functions",
            "Exponential Functions and Growth",
            "Function Notation and Composition",
            "Radical and Absolute Value Functions"
          ]
        },
        %{
          name: "Problem-Solving & Data Analysis",
          sections: [
            "Ratios, Rates, and Proportions",
            "Percentages",
            "Statistics — Central Tendency",
            "Statistics — Spread and Distribution",
            "Two-Way Tables",
            "Probability",
            "Data Interpretation — Graphs and Charts"
          ]
        },
        %{
          name: "Geometry & Trigonometry",
          sections: [
            "Lines and Angles",
            "Triangle Properties",
            "Area and Perimeter",
            "Circles — Arc, Sector, Central Angle",
            "Pythagorean Theorem",
            "Right Triangle Trigonometry",
            "Unit Circle and Special Angles"
          ]
        }
      ]
    },
    sat_rw: %{
      display_name: "Digital SAT — Reading & Writing",
      catalog_test_type: "sat",
      catalog_subject: "english_language",
      description:
        "Complete Digital SAT Reading & Writing preparation covering all four content domains. Adaptive practice sharpens comprehension, rhetoric, and grammar across short, focused passages.",
      generation_config: %{
        "prompt_context" =>
          "Digital SAT Reading & Writing — adaptive multistage exam, 54 questions across two 27-question modules (32 min each), 64 minutes total. All questions are 4-option multiple choice (A–D). Each question is paired with a short passage (25–150 words). Content domains: Craft and Structure (28%), Information and Ideas (26%), Expression of Ideas (20%), Standard English Conventions (26%).",
        "validation_rules" => %{
          "mcq_option_count" => 4,
          "answer_labels" => ["A", "B", "C", "D"]
        }
      },
      score_predictor_weights: %{
        "craft_and_structure" => 0.28,
        "information_and_ideas" => 0.26,
        "expression_of_ideas" => 0.20,
        "standard_english_conventions" => 0.26
      },
      suggested_chapters: [
        %{
          name: "Craft & Structure",
          sections: [
            "Words in Context — Meaning",
            "Words in Context — Tone and Connotation",
            "Text Structure and Purpose",
            "Cross-Text Connections"
          ]
        },
        %{
          name: "Information & Ideas",
          sections: [
            "Central Idea and Details",
            "Evidence — Textual Support",
            "Evidence — Graphic and Data Integration",
            "Inferences"
          ]
        },
        %{
          name: "Expression of Ideas",
          sections: [
            "Rhetorical Goals and Purpose",
            "Transitions",
            "Parallel Structure and Style"
          ]
        },
        %{
          name: "Standard English Conventions",
          sections: [
            "Punctuation — Commas",
            "Punctuation — Semicolons and Colons",
            "Subject-Verb Agreement",
            "Pronoun-Antecedent Agreement",
            "Verb Tense and Consistency",
            "Modifier Placement",
            "Run-Ons, Fragments, and Sentence Boundaries"
          ]
        }
      ]
    },
    act_math: %{
      display_name: "ACT — Mathematics",
      catalog_test_type: "act",
      catalog_subject: "mathematics",
      description:
        "Complete ACT Math preparation covering all six content domains. 60 multiple-choice questions in 60 minutes.",
      generation_config: %{
        "prompt_context" =>
          "ACT Math — linear exam, 60 five-option multiple-choice questions (A–E), 60 minutes, calculator permitted throughout. Questions test Pre-Algebra (23%), Elementary Algebra (17%), Intermediate Algebra and Coordinate Geometry (17%), Plane Geometry (23%), Trigonometry (7%), Statistics and Probability (13%).",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "pre_algebra" => 0.23,
        "elementary_algebra" => 0.17,
        "intermediate_algebra_coordinate_geometry" => 0.17,
        "plane_geometry" => 0.23,
        "trigonometry" => 0.07,
        "statistics_probability" => 0.13
      },
      suggested_chapters: [
        %{
          name: "Pre-Algebra",
          sections: [
            "Number Theory",
            "Fractions and Decimals",
            "Ratios and Proportions",
            "Percentages",
            "Basic Probability"
          ]
        },
        %{
          name: "Elementary Algebra",
          sections: [
            "Variables and Expressions",
            "Solving Linear Equations",
            "Inequalities",
            "Polynomials"
          ]
        },
        %{
          name: "Intermediate Algebra & Coordinate Geometry",
          sections: [
            "Quadratic Equations",
            "Systems of Equations",
            "Functions",
            "Coordinate Plane",
            "Slope and Linear Graphs"
          ]
        },
        %{
          name: "Plane Geometry",
          sections: ["Triangles", "Circles", "Polygons", "Area and Perimeter", "Volume"]
        },
        %{
          name: "Trigonometry",
          sections: ["Right Triangle Trig", "Trig Identities", "Unit Circle"]
        },
        %{
          name: "Statistics & Probability",
          sections: [
            "Mean, Median, Mode",
            "Data Interpretation",
            "Probability",
            "Counting and Combinations"
          ]
        }
      ]
    },
    act_english: %{
      display_name: "ACT — English",
      catalog_test_type: "act",
      catalog_subject: "english_language",
      description:
        "Complete ACT English preparation. 75 questions in 45 minutes across Usage/Mechanics and Rhetorical Skills.",
      generation_config: %{
        "prompt_context" =>
          "ACT English — 75 five-option multiple-choice questions (A–E), 45 minutes. Questions test Usage and Mechanics (53%): punctuation, grammar and usage, sentence structure; and Rhetorical Skills (47%): strategy, organization, style. Each question references an underlined portion of a prose passage.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{"usage_mechanics" => 0.53, "rhetorical_skills" => 0.47},
      suggested_chapters: [
        %{
          name: "Usage & Mechanics",
          sections: ["Punctuation", "Grammar and Usage", "Sentence Structure"]
        },
        %{name: "Rhetorical Skills", sections: ["Strategy", "Organization", "Style"]}
      ]
    },
    act_reading: %{
      display_name: "ACT — Reading",
      catalog_test_type: "act",
      catalog_subject: "reading",
      description:
        "Complete ACT Reading preparation. 40 questions in 35 minutes across four passage types.",
      generation_config: %{
        "prompt_context" =>
          "ACT Reading — 40 five-option multiple-choice questions (A–E), 35 minutes. Four passages (10 questions each): Literary Narrative, Social Studies, Humanities, Natural Sciences. Tests main idea, supporting detail, inference, vocabulary in context, comparative relationships, and author's voice.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "literary_narrative" => 0.25,
        "social_studies" => 0.25,
        "humanities" => 0.25,
        "natural_sciences" => 0.25
      },
      suggested_chapters: [
        %{
          name: "Literary Narrative",
          sections: ["Main Idea", "Character and Motivation", "Narrative Voice", "Inference"]
        },
        %{
          name: "Social Studies",
          sections: [
            "Central Argument",
            "Supporting Evidence",
            "Data Integration",
            "Comparative Analysis"
          ]
        },
        %{
          name: "Humanities",
          sections: ["Author's Perspective", "Vocabulary in Context", "Text Structure"]
        },
        %{
          name: "Natural Sciences",
          sections: ["Scientific Claims", "Data Interpretation", "Cause and Effect"]
        }
      ]
    },
    act_science: %{
      display_name: "ACT — Science",
      catalog_test_type: "act",
      catalog_subject: "science",
      description:
        "Complete ACT Science preparation. 40 questions in 35 minutes across data representation, research summaries, and conflicting viewpoints.",
      generation_config: %{
        "prompt_context" =>
          "ACT Science — 40 five-option multiple-choice questions (A–E), 35 minutes. Tests interpretation of scientific data in three formats: Data Representation (30–40%), Research Summaries (45–55%), Conflicting Viewpoints (15–20%). No recall of specific science facts required — all information is provided in the passages.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "data_representation" => 0.35,
        "research_summaries" => 0.50,
        "conflicting_viewpoints" => 0.15
      },
      suggested_chapters: [
        %{
          name: "Data Representation",
          sections: [
            "Reading Graphs and Tables",
            "Identifying Trends",
            "Interpolation and Extrapolation"
          ]
        },
        %{
          name: "Research Summaries",
          sections: ["Experimental Design", "Interpreting Results", "Comparing Experiments"]
        },
        %{
          name: "Conflicting Viewpoints",
          sections: ["Identifying Hypotheses", "Comparing Perspectives", "Evaluating Evidence"]
        }
      ]
    },
    gre_quant: %{
      display_name: "GRE — Quantitative Reasoning",
      catalog_test_type: "gre",
      catalog_subject: "mathematics",
      description:
        "Complete GRE Quantitative Reasoning preparation covering arithmetic, algebra, geometry, and data analysis.",
      generation_config: %{
        "prompt_context" =>
          "GRE Quantitative Reasoning — two 27-question sections (35 min each), 54 questions total. Question types: Quantitative Comparison (35%), Multiple Choice (30%), Multiple Select (25%), Numeric Entry (10%). Tests Arithmetic (25%), Algebra (25%), Geometry (25%), Data Analysis (25%). No calculator on some sections.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "arithmetic" => 0.25,
        "algebra" => 0.25,
        "geometry" => 0.25,
        "data_analysis" => 0.25
      },
      suggested_chapters: [
        %{
          name: "Arithmetic",
          sections: [
            "Integers",
            "Fractions and Decimals",
            "Exponents and Roots",
            "Percent and Ratio"
          ]
        },
        %{
          name: "Algebra",
          sections: [
            "Linear Equations",
            "Quadratic Equations",
            "Inequalities",
            "Functions and Graphs"
          ]
        },
        %{
          name: "Geometry",
          sections: ["Lines and Angles", "Triangles", "Circles", "Coordinate Geometry", "Volume"]
        },
        %{
          name: "Data Analysis",
          sections: [
            "Descriptive Statistics",
            "Distributions",
            "Probability",
            "Data Interpretation"
          ]
        }
      ]
    },
    gre_verbal: %{
      display_name: "GRE — Verbal Reasoning",
      catalog_test_type: "gre",
      catalog_subject: "verbal",
      description:
        "Complete GRE Verbal Reasoning preparation covering reading comprehension, text completion, and sentence equivalence.",
      generation_config: %{
        "prompt_context" =>
          "GRE Verbal Reasoning — two 27-question sections (30 min each). Question types: Reading Comprehension (50%), Text Completion (25%), Sentence Equivalence (25%). Tests ability to analyze and evaluate written material, synthesize information, and understand word relationships. Vocabulary is college-graduate level.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "reading_comprehension" => 0.50,
        "text_completion" => 0.25,
        "sentence_equivalence" => 0.25
      },
      suggested_chapters: [
        %{
          name: "Reading Comprehension",
          sections: [
            "Main Idea",
            "Inference",
            "Author's Purpose",
            "Text Structure",
            "Critical Reasoning"
          ]
        },
        %{
          name: "Text Completion",
          sections: ["Single Blank", "Double Blank", "Triple Blank", "Vocabulary in Context"]
        },
        %{name: "Sentence Equivalence", sections: ["Vocabulary", "Context Clues", "Synonyms"]}
      ]
    },
    lsat_lr: %{
      display_name: "LSAT — Logical Reasoning",
      catalog_test_type: "lsat",
      catalog_subject: "verbal",
      description:
        "Complete LSAT Logical Reasoning preparation covering argument analysis, assumption identification, and logical inference.",
      generation_config: %{
        "prompt_context" =>
          "LSAT Logical Reasoning — 4-option multiple-choice (A–D). Each question presents a short argument (2–4 sentences) followed by a question about it. Question types: Weaken, Strengthen, Assumption, Flaw, Inference, Main Point, Method of Reasoning, Parallel Reasoning, Paradox. Tests formal reasoning and argument analysis skills.",
        "validation_rules" => %{
          "mcq_option_count" => 5,
          "answer_labels" => ["A", "B", "C", "D", "E"]
        }
      },
      score_predictor_weights: %{
        "assumption_family" => 0.35,
        "inference_family" => 0.25,
        "flaw_method" => 0.20,
        "parallel_paradox" => 0.20
      },
      suggested_chapters: [
        %{
          name: "Assumption Family",
          sections: ["Necessary Assumption", "Sufficient Assumption", "Strengthen", "Weaken"]
        },
        %{
          name: "Inference Family",
          sections: ["Must Be True", "Most Strongly Supported", "Cannot Be True"]
        },
        %{
          name: "Flaw & Method",
          sections: [
            "Identifying Flaws",
            "Method of Reasoning",
            "Role of Statement",
            "Main Point"
          ]
        },
        %{
          name: "Parallel & Paradox",
          sections: ["Parallel Reasoning", "Parallel Flaw", "Resolve the Paradox"]
        }
      ]
    },
    ap_biology: %{
      display_name: "AP Biology",
      catalog_test_type: "ap_biology",
      catalog_subject: "science",
      description:
        "Complete AP Biology preparation covering all four Big Ideas and seven Science Practices aligned to the College Board curriculum framework.",
      generation_config: %{
        "prompt_context" =>
          "AP Biology — 60 four-option multiple-choice questions (A–D) plus 6 free-response questions. MCQ covers: Evolution (25%), Cellular Processes (25%), Genetics and Information Transfer (25%), Ecology (25%). Questions require application and analysis, not recall only. Expect data interpretation, experimental design, and claim-evidence-reasoning.",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "evolution" => 0.25,
        "cellular_processes" => 0.25,
        "genetics_information_transfer" => 0.25,
        "ecology" => 0.25
      },
      suggested_chapters: [
        %{
          name: "Evolution",
          sections: [
            "Natural Selection",
            "Evidence for Evolution",
            "Phylogenetics",
            "Population Genetics",
            "Speciation"
          ]
        },
        %{
          name: "Cellular Processes",
          sections: [
            "Cell Structure",
            "Membrane Transport",
            "Metabolism and Enzymes",
            "Photosynthesis",
            "Cellular Respiration",
            "Cell Communication"
          ]
        },
        %{
          name: "Genetics & Information Transfer",
          sections: [
            "DNA Structure and Replication",
            "Gene Expression",
            "Mutations and Regulation",
            "Mendelian Genetics",
            "Chromosomal Inheritance",
            "Biotechnology"
          ]
        },
        %{
          name: "Ecology",
          sections: [
            "Population Ecology",
            "Community Ecology",
            "Ecosystem Dynamics",
            "Energy Flow",
            "Biogeochemical Cycles"
          ]
        }
      ]
    },
    ap_calc_ab: %{
      display_name: "AP Calculus AB",
      catalog_test_type: "ap_calculus_ab",
      catalog_subject: "mathematics",
      description:
        "Complete AP Calculus AB preparation covering limits, derivatives, and integrals aligned to the College Board curriculum.",
      generation_config: %{
        "prompt_context" =>
          "AP Calculus AB — 45 four-option multiple-choice questions (A–D) plus 6 free-response questions. Topics: Limits and Continuity (10–12%), Differentiation — Definition and Fundamental Properties (10–12%), Differentiation — Composite, Implicit, Inverse (9–13%), Contextual Applications of Differentiation (10–15%), Analytical Applications of Differentiation (15–18%), Integration and Accumulation (17–20%), Differential Equations (6–12%), Applications of Integration (10–15%).",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "limits_continuity" => 0.11,
        "differentiation_basic" => 0.11,
        "differentiation_advanced" => 0.11,
        "contextual_differentiation" => 0.12,
        "analytical_differentiation" => 0.16,
        "integration" => 0.18,
        "differential_equations" => 0.09,
        "applications_integration" => 0.12
      },
      suggested_chapters: [
        %{
          name: "Limits & Continuity",
          sections: [
            "Limit Definition",
            "Limit Laws",
            "Continuity",
            "Squeeze Theorem",
            "Asymptotes"
          ]
        },
        %{
          name: "Differentiation",
          sections: [
            "Definition of Derivative",
            "Power Rule",
            "Product and Quotient Rules",
            "Chain Rule",
            "Implicit Differentiation",
            "Inverse Functions"
          ]
        },
        %{
          name: "Applications of Derivatives",
          sections: [
            "Related Rates",
            "Linear Approximation",
            "MVT and EVT",
            "Curve Sketching",
            "Optimization"
          ]
        },
        %{
          name: "Integration",
          sections: [
            "Riemann Sums",
            "Definite Integrals",
            "FTC",
            "U-Substitution",
            "Accumulation Functions"
          ]
        },
        %{
          name: "Differential Equations",
          sections: ["Slope Fields", "Separable Equations", "Exponential Models"]
        },
        %{
          name: "Applications of Integration",
          sections: ["Area Between Curves", "Volume — Disk and Washer", "Average Value", "Motion"]
        }
      ]
    },
    ap_calc_bc: %{
      display_name: "AP Calculus BC",
      catalog_test_type: "ap_calculus_bc",
      catalog_subject: "mathematics",
      description:
        "Complete AP Calculus BC preparation — all AB topics plus sequences and series, parametric equations, and polar curves.",
      generation_config: %{
        "prompt_context" =>
          "AP Calculus BC — 45 four-option multiple-choice questions (A–D) plus 6 free-response. Covers all AB topics plus: Parametric Equations, Polar Curves, Vector-Valued Functions, Sequences and Series (convergence tests, Taylor and Maclaurin series), and advanced integration techniques (integration by parts, partial fractions, improper integrals).",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "limits_differentiation" => 0.25,
        "integration" => 0.25,
        "differential_equations" => 0.10,
        "series_sequences" => 0.25,
        "parametric_polar" => 0.15
      },
      suggested_chapters: [
        %{
          name: "Limits & Differentiation",
          sections: ["All AB differentiation topics", "L'Hôpital's Rule", "Related Rates"]
        },
        %{
          name: "Integration Techniques",
          sections: [
            "U-Substitution",
            "Integration by Parts",
            "Partial Fractions",
            "Improper Integrals"
          ]
        },
        %{
          name: "Differential Equations",
          sections: ["Logistic Growth", "Euler's Method", "Slope Fields"]
        },
        %{
          name: "Sequences & Series",
          sections: [
            "Convergence Tests",
            "Power Series",
            "Taylor Series",
            "Maclaurin Series",
            "Error Bounds"
          ]
        },
        %{
          name: "Parametric, Polar & Vectors",
          sections: [
            "Parametric Equations",
            "Polar Coordinates",
            "Vector-Valued Functions",
            "Arc Length"
          ]
        }
      ]
    },
    ap_chemistry: %{
      display_name: "AP Chemistry",
      catalog_test_type: "ap_chemistry",
      catalog_subject: "science",
      description:
        "Complete AP Chemistry preparation covering all nine units of the College Board curriculum.",
      generation_config: %{
        "prompt_context" =>
          "AP Chemistry — 60 four-option multiple-choice questions (A–D) plus 7 free-response questions. Nine units: Atomic Structure (7–9%), Molecular and Ionic Bonding (7–9%), Intermolecular Forces (18–22%), Chemical Reactions (7–9%), Kinetics (7–9%), Thermodynamics (7–9%), Equilibrium (7–9%), Acids and Bases (11–15%), Electrochemistry (7–9%). Requires quantitative reasoning and application of chemistry principles.",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "atomic_structure" => 0.08,
        "bonding" => 0.08,
        "intermolecular_forces" => 0.20,
        "reactions" => 0.08,
        "kinetics" => 0.08,
        "thermodynamics" => 0.08,
        "equilibrium" => 0.08,
        "acids_bases" => 0.13,
        "electrochemistry" => 0.08
      },
      suggested_chapters: [
        %{
          name: "Atomic Structure & Properties",
          sections: [
            "Atomic Theory",
            "Electron Configuration",
            "Periodic Trends",
            "Photoelectron Spectroscopy"
          ]
        },
        %{
          name: "Molecular & Ionic Bonding",
          sections: ["Ionic Bonds", "Covalent Bonds", "VSEPR", "Hybridization", "Resonance"]
        },
        %{
          name: "Intermolecular Forces & Solutions",
          sections: [
            "IMF Types",
            "Physical Properties",
            "Solutions and Solubility",
            "Colligative Properties"
          ]
        },
        %{
          name: "Chemical Reactions",
          sections: [
            "Types of Reactions",
            "Net Ionic Equations",
            "Stoichiometry",
            "Limiting Reagents"
          ]
        },
        %{
          name: "Kinetics",
          sections: [
            "Reaction Rates",
            "Rate Laws",
            "Mechanisms",
            "Activation Energy",
            "Catalysis"
          ]
        },
        %{
          name: "Thermodynamics",
          sections: ["Enthalpy", "Entropy", "Gibbs Free Energy", "Hess's Law", "Calorimetry"]
        },
        %{
          name: "Equilibrium",
          sections: [
            "Kc and Kp",
            "Le Chatelier's Principle",
            "Solubility Equilibria",
            "ICE Tables"
          ]
        },
        %{
          name: "Acids & Bases",
          sections: [
            "pH and pOH",
            "Weak Acids and Bases",
            "Buffer Solutions",
            "Titrations",
            "Polyprotic Acids"
          ]
        },
        %{
          name: "Electrochemistry",
          sections: ["Galvanic Cells", "Cell Potential", "Electrolysis", "Faraday's Law"]
        }
      ]
    },
    ap_us_history: %{
      display_name: "AP US History (APUSH)",
      catalog_test_type: "ap_us_history",
      catalog_subject: "history",
      description:
        "Complete APUSH preparation covering all nine periods of American history from 1491 to the present.",
      generation_config: %{
        "prompt_context" =>
          "AP US History — 55 four-option multiple-choice questions (A–D) plus short-answer, document-based, and long-essay questions. Nine historical periods: 1491–1607, 1607–1754, 1754–1800, 1800–1848, 1844–1877, 1865–1898, 1890–1945, 1945–1980, 1980–present. Tests historical thinking skills: causation, continuity and change over time, comparison, and contextualization. MCQ uses stimulus-based documents and images.",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "colonial_period" => 0.10,
        "revolution_founding" => 0.10,
        "antebellum_civil_war" => 0.15,
        "gilded_age_progressive" => 0.15,
        "wwi_wwii" => 0.20,
        "cold_war_modern" => 0.20,
        "contemporary" => 0.10
      },
      suggested_chapters: [
        %{
          name: "Colonial Era (1491–1754)",
          sections: [
            "Native Societies",
            "European Colonization",
            "Colonial Societies",
            "Slavery and Labor"
          ]
        },
        %{
          name: "Revolution & Early Republic (1754–1800)",
          sections: [
            "Road to Revolution",
            "Revolutionary War",
            "Articles of Confederation",
            "Constitutional Convention",
            "Early National Period"
          ]
        },
        %{
          name: "Antebellum & Civil War (1800–1877)",
          sections: [
            "Jacksonian Democracy",
            "Manifest Destiny",
            "Sectionalism",
            "Civil War",
            "Reconstruction"
          ]
        },
        %{
          name: "Gilded Age & Progressive Era (1865–1920)",
          sections: [
            "Industrialization",
            "Immigration",
            "Populism",
            "Progressivism",
            "Imperialism"
          ]
        },
        %{
          name: "WWI, Interwar & WWII (1917–1945)",
          sections: ["WWI Home Front", "1920s Culture", "Great Depression", "New Deal", "WWII"]
        },
        %{
          name: "Cold War & Civil Rights (1945–1980)",
          sections: [
            "Early Cold War",
            "Korean War",
            "Civil Rights Movement",
            "Vietnam",
            "Great Society"
          ]
        },
        %{
          name: "Contemporary America (1980–present)",
          sections: [
            "Reagan Revolution",
            "End of Cold War",
            "Clinton Era",
            "9/11 and War on Terror",
            "Recent Decades"
          ]
        }
      ]
    },
    ap_english_lang: %{
      display_name: "AP English Language & Composition",
      catalog_test_type: "ap_english_lang",
      catalog_subject: "english_language",
      description:
        "Complete AP English Language & Composition preparation covering rhetoric, argumentation, and close reading of nonfiction texts.",
      generation_config: %{
        "prompt_context" =>
          "AP English Language and Composition — 45 four-option multiple-choice questions (A–D) plus three free-response essays (synthesis, rhetorical analysis, argument). MCQ tests: rhetorical situation, claims and evidence, reasoning and organization, style. Students read and analyze nonfiction prose passages from a range of historical periods and disciplines.",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "rhetorical_situation" => 0.30,
        "claims_evidence" => 0.30,
        "reasoning_organization" => 0.20,
        "style" => 0.20
      },
      suggested_chapters: [
        %{
          name: "Rhetorical Situation",
          sections: [
            "Author, Purpose, Audience",
            "Context and Exigence",
            "Genre and Medium",
            "Appeals (Ethos, Pathos, Logos)"
          ]
        },
        %{
          name: "Claims & Evidence",
          sections: [
            "Types of Claims",
            "Evidence Selection and Use",
            "Source Evaluation",
            "Synthesis"
          ]
        },
        %{
          name: "Reasoning & Organization",
          sections: [
            "Argument Structure",
            "Logical Fallacies",
            "Transitions and Coherence",
            "Counterargument"
          ]
        },
        %{
          name: "Style & Tone",
          sections: [
            "Diction and Syntax",
            "Figurative Language",
            "Tone and Irony",
            "Sentence Variety"
          ]
        }
      ]
    },
    ap_physics: %{
      display_name: "AP Physics 1",
      catalog_test_type: "ap_physics_1",
      catalog_subject: "science",
      description:
        "Complete AP Physics 1 preparation covering mechanics, waves, and introductory electricity.",
      generation_config: %{
        "prompt_context" =>
          "AP Physics 1 (algebra-based) — 50 four-option multiple-choice questions (A–D) including 5 multi-select, plus 5 free-response questions. Topics: Kinematics (12–18%), Dynamics (16–20%), Circular Motion and Gravitation (6–8%), Energy (20–28%), Momentum (12–18%), Simple Harmonic Motion (4–6%), Waves (6–8%), Electrostatics (10–14%). Questions emphasize conceptual understanding and quantitative reasoning over rote formula application.",
        "validation_rules" => %{"mcq_option_count" => 4, "answer_labels" => ["A", "B", "C", "D"]}
      },
      score_predictor_weights: %{
        "kinematics" => 0.15,
        "dynamics" => 0.18,
        "circular_motion_gravitation" => 0.07,
        "energy" => 0.24,
        "momentum" => 0.15,
        "waves_shm" => 0.10,
        "electrostatics" => 0.12
      },
      suggested_chapters: [
        %{
          name: "Kinematics",
          sections: [
            "Displacement and Velocity",
            "Acceleration",
            "Projectile Motion",
            "Graphs of Motion"
          ]
        },
        %{
          name: "Dynamics",
          sections: ["Newton's Laws", "Free Body Diagrams", "Friction", "Normal Force", "Tension"]
        },
        %{
          name: "Circular Motion & Gravitation",
          sections: [
            "Uniform Circular Motion",
            "Centripetal Force",
            "Gravitational Force",
            "Orbital Motion"
          ]
        },
        %{
          name: "Energy",
          sections: [
            "Work and Power",
            "Kinetic Energy",
            "Potential Energy",
            "Conservation of Energy",
            "Spring Energy"
          ]
        },
        %{
          name: "Momentum",
          sections: [
            "Linear Momentum",
            "Impulse",
            "Conservation of Momentum",
            "Elastic and Inelastic Collisions"
          ]
        },
        %{
          name: "Waves & Simple Harmonic Motion",
          sections: [
            "Wave Properties",
            "Standing Waves",
            "Sound",
            "Period and Frequency",
            "Pendulums"
          ]
        },
        %{
          name: "Electrostatics",
          sections: ["Electric Charge", "Coulomb's Law", "Electric Fields", "Electric Potential"]
        }
      ]
    }
  }

  @doc """
  Detects a known standardized test from the course name.
  Returns `{:ok, profile}` or `:unknown`.
  """
  @spec detect(String.t()) :: {:ok, profile()} | :unknown
  def detect(name) when is_binary(name) do
    case Enum.find(@patterns, fn {pattern, _key} -> Regex.match?(pattern, name) end) do
      {_pattern, key} -> {:ok, Map.fetch!(@profiles, key)}
      nil -> :unknown
    end
  end

  def detect(_), do: :unknown

  @doc """
  Returns all profile keys and display names, for use in dropdowns.
  """
  @spec all_display_names() :: [{String.t(), String.t()}]
  def all_display_names do
    @profiles
    |> Enum.map(fn {key, p} -> {to_string(key), p.display_name} end)
    |> Enum.sort_by(&elem(&1, 1))
  end
end
