import Foundation

struct IndustryProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let systemPrompt: String
    let vocabularyHints: [String]

    static let general = IndustryProfile(
        id: "general",
        name: "General",
        icon: "text.bubble",
        systemPrompt: """
        You are a professional writing assistant. Apply all baseline dictation cleanup. \
        Produce clean, well-structured prose suitable for general business communication.
        """,
        vocabularyHints: []
    )

    static let legal = IndustryProfile(
        id: "legal",
        name: "Legal",
        icon: "building.columns",
        systemPrompt: """
        You are a legal writing assistant. Polish dictated text into professional legal \
        language. Use proper legal terminology where appropriate (e.g., "hereinafter", \
        "pursuant to", "notwithstanding", "whereas"). Format as appropriate for legal \
        correspondence, memoranda, or contracts. Preserve the original meaning precisely.
        """,
        vocabularyHints: [
            // Latin terms (most mangled by recognizers)
            "estoppel", "mens rea", "actus reus", "habeas corpus", "subpoena",
            "amicus curiae", "pro bono", "prima facie", "res judicata", "stare decisis",
            "voir dire", "certiorari", "mandamus", "de facto", "de jure",
            "ex parte", "in camera", "nolo contendere", "pro se", "quid pro quo",
            "bona fide", "inter alia", "modus operandi", "ipso facto", "ad hoc",
            "sui generis", "ultra vires", "ab initio", "caveat emptor",
            // Parties & roles
            "plaintiff", "defendant", "appellant", "respondent", "petitioner",
            "complainant", "litigant", "counsel", "co-counsel", "paralegal",
            "deponent", "affiant", "witness", "expert witness", "mediator",
            "arbitrator", "adjudicator", "magistrate", "bailiff",
            // Documents & filings
            "affidavit", "deposition", "interrogatories", "subpoena duces tecum",
            "complaint", "answer", "counterclaim", "cross-claim", "motion",
            "brief", "memorandum", "stipulation", "pleading", "discovery",
            "exhibit", "addendum", "codicil", "retainer", "engagement letter",
            // Concepts
            "indemnification", "tortfeasor", "jurisprudence", "adjudication",
            "arbitration", "injunction", "litigation", "statute", "precedent",
            "jurisdiction", "tort", "breach", "negligence", "liability", "damages",
            "remedy", "covenant", "lien", "collateral", "escrow", "fiduciary",
            "due process", "standing", "venue", "cause of action", "burden of proof",
            "preponderance", "beyond reasonable doubt", "mitigating", "aggravating",
            "malfeasance", "misfeasance", "nonfeasance", "proximate cause",
            "statute of limitations", "double jeopardy", "eminent domain",
            "intellectual property", "trade secret", "non-compete", "NDA",
            "force majeure", "liquidated damages", "punitive damages",
            "class action", "summary judgment", "default judgment",
            "settlement", "mediation", "plea bargain", "arraignment"
        ]
    )

    static let accounting = IndustryProfile(
        id: "accounting",
        name: "Accounting",
        icon: "dollarsign.circle",
        systemPrompt: """
        You are an accounting and finance writing assistant. Polish dictated text using \
        professional accounting terminology and formatting. Use proper financial terms \
        (e.g., "accounts receivable", "amortization", "accrual basis"). Format numbers, \
        currency amounts, and percentages consistently. Structure content appropriately \
        for financial reports, memos, or correspondence.
        """,
        vocabularyHints: [
            // Standards & frameworks
            "GAAP", "IFRS", "SOX", "Sarbanes-Oxley", "FASB", "AICPA", "PCAOB",
            "ASC 606", "ASC 842", "GASB", "SEC", "10-K", "10-Q", "8-K",
            // Core accounting
            "amortization", "depreciation", "accrual", "deferral", "accrual basis",
            "cash basis", "double entry", "debit", "credit", "T-account",
            "accounts receivable", "accounts payable", "general ledger", "subledger",
            "trial balance", "chart of accounts", "journal entry", "adjusting entry",
            "closing entry", "reconciliation", "bank reconciliation",
            // Financial statements
            "balance sheet", "income statement", "cash flow statement",
            "statement of equity", "retained earnings", "comprehensive income",
            "working capital", "current ratio", "quick ratio", "debt-to-equity",
            // Metrics & ratios
            "EBITDA", "EBIT", "ROI", "ROE", "ROA", "EPS", "P/E ratio",
            "gross margin", "net margin", "operating margin", "free cash flow",
            "revenue recognition", "cost of goods sold", "COGS", "SG&A",
            "overhead", "variable cost", "fixed cost", "marginal cost",
            "break-even", "contribution margin", "net income", "gross profit",
            // Tax & audit
            "audit", "compliance", "internal controls", "material weakness",
            "qualified opinion", "unqualified opinion", "going concern",
            "deferred tax", "tax liability", "tax provision", "withholding",
            "W-2", "W-9", "1099", "1040", "Schedule C", "Schedule K-1",
            "capital gains", "ordinary income", "AMT", "NOL", "carryforward",
            // Corporate finance
            "capitalization", "write-off", "write-down", "impairment",
            "provision", "contingency", "goodwill", "intangible asset",
            "fiduciary", "fiscal year", "fiscal quarter", "year over year",
            "budget variance", "forecast", "pro forma", "cap table", "dilution"
        ]
    )

    static let engineering = IndustryProfile(
        id: "engineering",
        name: "Engineering",
        icon: "gearshape.2",
        systemPrompt: """
        You are a technical engineering writing assistant. Polish dictated text using \
        professional engineering terminology. Use precise technical language appropriate \
        for engineering documentation, specifications, or reports. Properly format \
        measurements, units, tolerances, and technical specifications.
        """,
        vocabularyHints: [
            // HVAC & mechanical
            "HVAC", "BTU", "CFM", "SEER", "EER", "AFUE", "tonnage", "refrigerant",
            "R-410A", "R-22", "compressor", "condenser", "evaporator", "ductwork",
            "air handler", "thermostat", "heat pump", "chiller", "boiler", "furnace",
            "damper", "plenum", "diffuser", "return air", "supply air", "makeup air",
            "static pressure", "delta T", "superheat", "subcooling", "enthalpy",
            // Structural & civil
            "structural", "load bearing", "dead load", "live load", "wind load",
            "seismic", "moment", "shear force", "bending moment", "deflection",
            "reinforced concrete", "prestressed", "post-tensioned", "I-beam", "W-flange",
            "HSS", "rebar", "aggregate", "PSI", "compressive strength",
            // Design & analysis
            "CAD", "CAM", "CAE", "FEA", "finite element", "CFD", "SolidWorks",
            "AutoCAD", "Revit", "CATIA", "Inventor", "Fusion 360", "BIM",
            "tolerance", "GD&T", "specification", "bill of materials", "BOM",
            "schematic", "blueprint", "prototype", "iteration", "design review",
            // Materials & properties
            "tensile strength", "yield strength", "fatigue", "creep", "hardness",
            "elasticity", "modulus", "Young's modulus", "Poisson's ratio",
            "alloy", "composite", "carbon fiber", "fiberglass", "stainless steel",
            "galvanized", "anodized", "tempered", "quenched",
            // Physics & thermo
            "thermodynamics", "kinematics", "dynamics", "fluid mechanics",
            "hydraulics", "pneumatics", "Bernoulli", "Reynolds number",
            "laminar", "turbulent", "viscosity", "coefficient of friction",
            "torque", "RPM", "horsepower", "kilowatt", "megapascal",
            // Process
            "commissioning", "decommissioning", "calibration", "P&ID",
            "ISO", "ASME", "ANSI", "ASTM", "IEEE", "NFPA", "UL"
        ]
    )

    static let science = IndustryProfile(
        id: "science",
        name: "Science",
        icon: "atom",
        systemPrompt: """
        You are a scientific writing assistant. Polish dictated text into professional \
        scientific language. Use precise scientific terminology. Format appropriately \
        for research papers, lab reports, or scientific correspondence. Use passive \
        voice where conventional in scientific writing. Properly format chemical \
        formulas, equations, units, and measurements.
        """,
        vocabularyHints: [
            // Research methodology
            "hypothesis", "null hypothesis", "methodology", "empirical", "theoretical",
            "quantitative", "qualitative", "longitudinal", "cross-sectional",
            "meta-analysis", "systematic review", "peer review", "reproducibility",
            "double-blind", "placebo", "control group", "experimental group",
            "independent variable", "dependent variable", "confounding variable",
            // Statistics
            "statistical significance", "p-value", "confidence interval",
            "standard deviation", "variance", "mean", "median", "regression",
            "ANOVA", "chi-square", "t-test", "F-test", "Bayesian",
            "correlation", "causation", "coefficient", "R-squared",
            "sample size", "power analysis", "effect size", "outlier",
            // Chemistry
            "spectroscopy", "chromatography", "mass spectrometry", "NMR",
            "centrifuge", "titration", "reagent", "catalyst", "substrate",
            "isotope", "molecule", "polymer", "monomer", "covalent", "ionic",
            "molar", "molarity", "mole", "Avogadro", "stoichiometry",
            "pH", "buffer", "solute", "solvent", "precipitate", "distillation",
            // Biology
            "genome", "proteome", "phenotype", "genotype", "allele",
            "mitochondria", "ribosome", "cytoplasm", "nucleus", "membrane",
            "DNA", "RNA", "mRNA", "CRISPR", "PCR", "gel electrophoresis",
            "in vitro", "in vivo", "in silico", "cell culture", "assay",
            "antibody", "antigen", "enzyme", "protein", "amino acid",
            // Physics
            "photosynthesis", "entropy", "enthalpy", "thermodynamic", "kinetic",
            "equilibrium", "quantum", "wavelength", "frequency", "amplitude",
            "Planck", "Heisenberg", "Schrödinger", "Bohr", "Coulomb",
            "electromagnetic", "photon", "electron", "neutron", "proton",
            // Publication
            "abstract", "introduction", "methods", "results", "discussion",
            "conclusion", "supplementary", "citation", "DOI", "impact factor",
            "preprint", "arXiv", "bioRxiv", "PubMed", "Nature", "Science"
        ]
    )

    static let businessManagement = IndustryProfile(
        id: "business_management",
        name: "Business Management",
        icon: "briefcase",
        systemPrompt: """
        You are a business management writing assistant. Polish dictated text into \
        professional business language. Use appropriate business terminology and \
        management concepts. Format for business plans, reports, memos, or executive \
        communications. Maintain a professional, confident tone. Structure content \
        with clear points and actionable items where appropriate.
        """,
        vocabularyHints: [
            // Metrics & KPIs
            "KPI", "OKR", "ROI", "ROE", "ROA", "CAGR", "MRR", "ARR", "LTV",
            "CAC", "NPS", "CSAT", "churn", "attrition", "retention rate",
            "gross margin", "net margin", "EBITDA", "run rate", "burn rate",
            // Strategy & planning
            "SWOT analysis", "PESTLE", "Porter's Five Forces", "BCG matrix",
            "competitive advantage", "value proposition", "core competency",
            "strategic initiative", "mission statement", "vision statement",
            "go-to-market", "GTM", "TAM", "SAM", "SOM", "market share",
            "blue ocean", "red ocean", "first mover", "moat", "pivot",
            // Operations
            "P&L", "profit and loss", "bottom line", "top line", "revenue",
            "operational efficiency", "scalability", "throughput", "utilization",
            "lean", "Six Sigma", "Kaizen", "DMAIC", "value stream",
            "SLA", "service level agreement", "SOP", "standard operating procedure",
            // Management
            "stakeholder", "deliverable", "milestone", "roadmap", "backlog",
            "bandwidth", "pipeline", "funnel", "onboarding", "offboarding",
            "change management", "risk mitigation", "due diligence",
            "cross-functional", "matrix organization", "flat organization",
            "span of control", "delegation", "empowerment", "accountability",
            // Finance & reporting
            "fiscal quarter", "fiscal year", "year over year", "YoY",
            "quarter over quarter", "QoQ", "month over month", "MoM",
            "budget variance", "forecast", "pro forma", "working capital",
            "capex", "opex", "headcount", "FTE", "full-time equivalent",
            // Agile & project management
            "agile", "scrum", "kanban", "sprint", "standup", "retrospective",
            "epic", "user story", "story points", "velocity", "burndown",
            "product owner", "scrum master", "backlog grooming", "Jira",
            "Gantt chart", "critical path", "WBS", "work breakdown structure"
        ]
    )

    static let salesMarketing = IndustryProfile(
        id: "sales_marketing",
        name: "Sales & Marketing",
        icon: "megaphone",
        systemPrompt: """
        You are a sales and marketing writing assistant. Polish dictated text into \
        compelling, professional sales or marketing language. Use industry terminology \
        appropriately. For sales communications, maintain a persuasive yet professional \
        tone. For marketing copy, ensure clarity and impact. Format appropriately for \
        proposals, pitches, campaigns, or client communications.
        """,
        vocabularyHints: [
            // Digital marketing metrics
            "CTR", "click-through rate", "CPA", "cost per acquisition",
            "CPM", "cost per mille", "CPC", "cost per click",
            "ROAS", "return on ad spend", "ROI", "conversion rate",
            "bounce rate", "session duration", "page views", "impressions",
            "reach", "frequency", "engagement rate", "open rate",
            // Sales pipeline
            "lead generation", "lead nurturing", "lead scoring", "funnel",
            "pipeline", "prospect", "outreach", "cold call", "warm lead",
            "qualified lead", "MQL", "SQL", "SAL", "opportunity",
            "discovery call", "demo", "proposal", "close rate", "win rate",
            "upsell", "cross-sell", "churn rate", "retention", "renewal",
            "ARR", "MRR", "ACV", "TCV", "quota", "attainment",
            "territory", "account executive", "AE", "SDR", "BDR",
            // Marketing strategy
            "brand awareness", "market penetration", "segmentation", "persona",
            "buyer journey", "awareness", "consideration", "decision",
            "value proposition", "unique selling proposition", "USP",
            "positioning", "differentiation", "go-to-market", "GTM",
            "TAM", "SAM", "SOM", "market fit", "product market fit",
            // Channels & tactics
            "SEO", "SEM", "PPC", "organic", "paid media", "earned media",
            "content marketing", "inbound", "outbound", "ABM", "account-based",
            "email marketing", "drip campaign", "nurture sequence",
            "social media", "influencer", "UGC", "user-generated content",
            "webinar", "whitepaper", "case study", "testimonial",
            "call to action", "CTA", "landing page", "squeeze page",
            "A/B testing", "multivariate", "attribution", "multi-touch",
            "omnichannel", "retargeting", "remarketing", "lookalike audience",
            // Tools & platforms
            "CRM", "Salesforce", "HubSpot", "Marketo", "Pardot",
            "Google Analytics", "GA4", "Google Ads", "Meta Ads", "LinkedIn Ads",
            "Mailchimp", "Klaviyo", "Shopify", "WordPress", "Webflow"
        ]
    )

    static let softwareProgramming = IndustryProfile(
        id: "software_programming",
        name: "Software & Programming",
        icon: "chevron.left.forwardslash.chevron.right",
        systemPrompt: """
        You are a software engineering writing assistant. Polish dictated text using \
        professional software development terminology. This may be code comments, \
        documentation, technical specifications, pull request descriptions, commit \
        messages, or developer communications. Use proper technical terms for \
        programming concepts, design patterns, and software architecture. Format \
        code references with backticks where appropriate. Preserve any code snippets \
        exactly as spoken.
        """,
        vocabularyHints: [
            // Version control
            "Git", "git pull", "git push", "git commit", "git merge", "git rebase",
            "git stash", "git clone", "git checkout", "git branch", "git diff",
            "pull request", "merge conflict", "cherry pick", "HEAD", "origin", "upstream",
            // APIs & protocols
            "API", "REST", "RESTful", "GraphQL", "gRPC", "WebSocket", "webhook",
            "OAuth", "JWT", "CORS", "HTTPS", "SSL", "TLS", "endpoint",
            // Architecture
            "microservices", "monolith", "serverless", "MVC", "MVVM", "MVP",
            "dependency injection", "singleton", "observer pattern", "pub sub",
            // DevOps & infra
            "CI/CD", "DevOps", "Kubernetes", "K8s", "Docker", "container",
            "AWS", "S3", "EC2", "Lambda", "Azure", "GCP", "Terraform",
            "NGINX", "load balancer", "CDN", "DNS", "SSH", "YAML", "JSON",
            // Languages & tools
            "JavaScript", "TypeScript", "Python", "Swift", "Rust", "Go", "Java",
            "React", "Node", "npm", "yarn", "pip", "Xcode", "VS Code",
            "PostgreSQL", "MySQL", "MongoDB", "Redis", "SQLite", "NoSQL",
            // Programming concepts
            "async", "await", "callback", "promise", "closure", "lambda",
            "polymorphism", "inheritance", "encapsulation", "abstraction",
            "boolean", "integer", "string", "array", "dictionary", "hashmap",
            "null", "nil", "undefined", "enum", "struct", "class", "interface",
            "refactor", "linting", "transpile", "compile", "runtime", "SDK",
            "framework", "library", "module", "package", "dependency",
            // Testing & debugging
            "unit test", "integration test", "end-to-end", "E2E", "TDD", "BDD",
            "stack trace", "debug", "breakpoint", "console log", "stderr", "stdout",
            "CI", "CD", "pipeline", "deploy", "rollback", "staging", "production",
            // Common phrases recognizer mangles
            "localhost", "config", "env", "dotenv", "cron job", "regex",
            "backend", "frontend", "full stack", "tech debt", "code review",
            "sprint", "standup", "retro", "kanban", "scrum", "agile"
        ]
    )

    static let hardware = IndustryProfile(
        id: "hardware",
        name: "Hardware & Electronics",
        icon: "cpu",
        systemPrompt: """
        You are a hardware and electronics engineering writing assistant. Polish \
        dictated text using professional hardware and electronics terminology. Format \
        appropriately for technical documentation, specifications, or reports. Properly \
        format component values, pin configurations, and electrical units.
        """,
        vocabularyHints: [
            // Components
            "resistor", "capacitor", "inductor", "transistor", "diode", "LED",
            "MOSFET", "IGBT", "BJT", "op-amp", "comparator", "regulator",
            "relay", "solenoid", "transformer", "fuse", "varistor", "thyristor",
            "crystal oscillator", "ceramic resonator", "ferrite bead",
            // ICs & processors
            "FPGA", "ASIC", "SoC", "MCU", "microcontroller", "microprocessor",
            "ARM", "RISC-V", "x86", "DSP", "GPU", "CPLD",
            "Arduino", "Raspberry Pi", "ESP32", "STM32", "PIC", "AVR",
            // Interfaces & protocols
            "GPIO", "SPI", "I2C", "UART", "USB", "USB-C", "JTAG", "SWD",
            "Ethernet", "CAN bus", "RS-232", "RS-485", "Modbus", "HDMI",
            "PCIe", "SDIO", "MIPI", "LVDS", "I2S", "PWM", "analog",
            // PCB & manufacturing
            "PCB", "printed circuit board", "schematic", "layout", "Gerber",
            "BOM", "bill of materials", "footprint", "land pattern",
            "through-hole", "THT", "surface mount", "SMT", "SMD",
            "soldering", "reflow", "wave solder", "pick and place",
            "via", "trace", "copper pour", "ground plane", "impedance control",
            "DRC", "design rule check", "ERC", "electrical rule check",
            // Test & measurement
            "oscilloscope", "multimeter", "logic analyzer", "spectrum analyzer",
            "signal generator", "power supply", "bench supply",
            "ADC", "DAC", "SNR", "THD", "bandwidth", "sample rate",
            "Nyquist", "aliasing", "decibel", "dBm", "eye diagram",
            // Firmware & embedded
            "firmware", "embedded", "RTOS", "real-time", "interrupt", "ISR",
            "DMA", "watchdog", "bootloader", "flash memory", "EEPROM",
            "clock speed", "MHz", "GHz", "baud rate", "bit rate",
            // Design tools
            "KiCad", "Altium", "Eagle", "OrCAD", "LTspice", "SPICE",
            "EDA", "Mentor Graphics", "Cadence", "Zuken"
        ]
    )

    static let manufacturing = IndustryProfile(
        id: "manufacturing",
        name: "Manufacturing",
        icon: "hammer",
        systemPrompt: """
        You are a manufacturing industry writing assistant. Polish dictated text using \
        professional manufacturing terminology. Format appropriately for production \
        reports, quality documentation, standard operating procedures, or manufacturing \
        specifications. Use proper units, tolerances, and technical terms.
        """,
        vocabularyHints: [
            // Processes
            "CNC", "injection molding", "blow molding", "rotational molding",
            "die casting", "sand casting", "investment casting", "lost wax",
            "extrusion", "stamping", "forging", "welding", "MIG", "TIG", "arc",
            "laser cutting", "waterjet", "EDM", "wire EDM", "broaching",
            "turning", "milling", "drilling", "grinding", "honing", "lapping",
            "3D printing", "additive manufacturing", "SLA", "FDM", "SLS", "DMLS",
            // Quality
            "GD&T", "geometric dimensioning and tolerancing", "tolerance",
            "quality control", "QC", "quality assurance", "QA",
            "ISO 9001", "ISO 14001", "IATF 16949", "AS9100",
            "first article inspection", "FAI", "PPAP", "APQP", "FMEA",
            "SPC", "statistical process control", "control chart", "Cpk", "Ppk",
            "CMM", "coordinate measuring machine", "gauge R&R", "calibration",
            // Lean & continuous improvement
            "lean manufacturing", "Six Sigma", "Kaizen", "5S", "Kanban",
            "value stream mapping", "VSM", "DMAIC", "PDCA", "poka-yoke",
            "andon", "gemba", "muda", "muri", "mura", "heijunka",
            "just in time", "JIT", "single piece flow", "bottleneck",
            // Production
            "bill of materials", "BOM", "work order", "batch", "lot number",
            "yield rate", "scrap rate", "rework", "cycle time", "takt time",
            "throughput", "OEE", "overall equipment effectiveness",
            "downtime", "changeover", "setup time", "run time",
            "preventive maintenance", "PM", "predictive maintenance",
            "TPM", "total productive maintenance", "MTBF", "MTTR",
            // Materials
            "tooling", "fixture", "jig", "die", "mold", "punch",
            "heat treatment", "annealing", "tempering", "hardening",
            "quenching", "carburizing", "nitriding", "case hardening",
            "hardness", "Rockwell", "Brinell", "Vickers", "Shore",
            "tensile", "yield", "elongation", "ductility", "brittleness"
        ]
    )

    static let construction = IndustryProfile(
        id: "construction",
        name: "Construction",
        icon: "building.2",
        systemPrompt: """
        You are a construction industry writing assistant. Polish dictated text using \
        professional construction terminology. Format appropriately for project \
        reports, RFIs, submittals, change orders, or site documentation. Use proper \
        construction terms, measurement units, and building codes references.
        """,
        vocabularyHints: [
            // Project documents
            "RFI", "request for information", "submittal", "transmittal",
            "change order", "CO", "punch list", "closeout", "substantial completion",
            "notice to proceed", "NTP", "certificate of occupancy", "CO",
            "as-built", "shop drawing", "elevation", "section", "detail",
            "specifications", "spec book", "Division 1", "CSI", "MasterFormat",
            // Contracts & finance
            "bid", "estimate", "proposal", "scope of work", "SOW",
            "GMP", "guaranteed maximum price", "lump sum", "cost plus",
            "retainage", "lien waiver", "AIA", "pay application",
            "liquidated damages", "bonding", "surety", "performance bond",
            "prevailing wage", "Davis-Bacon", "certified payroll",
            // Roles
            "general contractor", "GC", "subcontractor", "sub",
            "superintendent", "foreman", "project manager", "PM",
            "owner's rep", "architect", "structural engineer",
            "geotechnical", "surveyor", "inspector",
            // Structural & site
            "concrete", "rebar", "formwork", "shoring", "scaffolding",
            "excavation", "grading", "backfill", "compaction", "dewatering",
            "foundation", "footing", "pile", "caisson", "grade beam",
            "slab on grade", "post-tension", "tilt-up", "precast",
            "framing", "stud", "joist", "truss", "header", "beam", "column",
            // Trades & systems
            "HVAC", "mechanical", "electrical", "plumbing", "MEP",
            "fire protection", "sprinkler", "fire alarm", "low voltage",
            "drywall", "finish", "millwork", "casework", "flooring",
            "roofing", "waterproofing", "cladding", "curtain wall", "glazing",
            "insulation", "R-value", "vapor barrier", "flashing",
            // Codes & safety
            "building code", "IBC", "IRC", "NEC", "NFPA", "ADA",
            "OSHA", "safety", "PPE", "fall protection", "SWPPP",
            "stormwater", "erosion control", "environmental", "LEED",
            // Scheduling
            "critical path", "CPM", "Gantt chart", "baseline schedule",
            "float", "slack", "milestone", "predecessor", "successor",
            "Primavera", "P6", "Procore", "Bluebeam", "PlanGrid"
        ]
    )

    static let medical = IndustryProfile(
        id: "medical",
        name: "Medical & Healthcare",
        icon: "stethoscope",
        systemPrompt: """
        You are a medical and healthcare writing assistant. Polish dictated text using \
        professional medical terminology. Format appropriately for clinical notes, \
        medical reports, referral letters, or healthcare documentation. Use proper \
        medical abbreviations and terminology. Maintain HIPAA-compliant language practices.
        """,
        vocabularyHints: [
            // Clinical documentation
            "chief complaint", "CC", "history of present illness", "HPI",
            "review of systems", "ROS", "physical examination", "PE",
            "assessment and plan", "A&P", "differential diagnosis", "DDx",
            "subjective", "objective", "SOAP note", "progress note",
            "discharge summary", "operative report", "consultation",
            // Diagnoses & conditions
            "diagnosis", "prognosis", "etiology", "pathology", "pathogenesis",
            "symptom", "syndrome", "chronic", "acute", "subacute",
            "benign", "malignant", "metastatic", "idiopathic", "iatrogenic",
            "contraindication", "comorbidity", "sequela", "exacerbation",
            "remission", "relapse", "prodromal", "asymptomatic",
            // Anatomy & positioning
            "bilateral", "unilateral", "anterior", "posterior", "lateral",
            "medial", "proximal", "distal", "superior", "inferior",
            "dorsal", "ventral", "supine", "prone", "contralateral",
            "ipsilateral", "subcutaneous", "intramuscular", "intravenous",
            "sublingual", "intrathecal", "epidural", "transdermal",
            // Vitals & conditions
            "hypertension", "hypotension", "tachycardia", "bradycardia",
            "tachypnea", "dyspnea", "hypoxia", "cyanosis", "diaphoresis",
            "edema", "inflammation", "necrosis", "ischemia", "hemorrhage",
            "embolism", "thrombosis", "aneurysm", "stenosis", "fibrillation",
            // Medications
            "prescription", "Rx", "dosage", "milligrams", "mg", "mcg",
            "PRN", "BID", "TID", "QID", "QHS", "PO", "IV", "IM", "SQ",
            "titrate", "taper", "loading dose", "maintenance dose",
            "contraindicated", "adverse reaction", "anaphylaxis",
            // Labs & diagnostics
            "CBC", "complete blood count", "BMP", "CMP", "lipid panel",
            "hemoglobin", "hematocrit", "WBC", "platelet", "creatinine",
            "BUN", "troponin", "procalcitonin", "TSH", "HbA1c", "INR",
            "MRI", "CT scan", "X-ray", "ultrasound", "PET scan",
            "EKG", "ECG", "echocardiogram", "EEG", "EMG",
            "biopsy", "cytology", "histology", "culture", "sensitivity",
            // Systems & compliance
            "EMR", "EHR", "CPOE", "HL7", "FHIR",
            "ICD-10", "CPT", "HCPCS", "DRG", "RVU",
            "HIPAA", "PHI", "protected health information",
            "meaningful use", "MIPS", "MACRA", "value-based care",
            // Specialties
            "cardiology", "pulmonology", "neurology", "orthopedics",
            "gastroenterology", "endocrinology", "nephrology", "oncology",
            "pediatrics", "geriatrics", "psychiatry", "dermatology",
            "ophthalmology", "otolaryngology", "ENT", "radiology", "pathology"
        ]
    )

    static let allProfiles: [IndustryProfile] = [
        .general, .legal, .accounting, .engineering, .science,
        .businessManagement, .salesMarketing, .softwareProgramming,
        .hardware, .manufacturing, .construction, .medical
    ]
}
