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
            "estoppel", "indemnification", "tortfeasor", "mens rea", "actus reus",
            "habeas corpus", "subpoena", "deposition", "affidavit", "jurisprudence",
            "adjudication", "arbitration", "plaintiff", "defendant", "appellant",
            "respondent", "amicus curiae", "pro bono", "prima facie", "fiduciary",
            "injunction", "litigation", "statute", "precedent", "jurisdiction",
            "tort", "breach", "negligence", "liability", "damages", "remedy",
            "stipulation", "covenant", "lien", "collateral", "escrow"
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
            "GAAP", "IFRS", "amortization", "depreciation", "accrual", "deferral",
            "accounts receivable", "accounts payable", "general ledger", "trial balance",
            "balance sheet", "income statement", "cash flow", "equity", "liability",
            "asset", "journal entry", "reconciliation", "audit", "compliance",
            "fiduciary", "fiscal year", "quarterly", "EBITDA", "ROI", "ROE",
            "capitalization", "write-off", "provision", "contingency", "goodwill",
            "revenue recognition", "cost of goods sold", "gross margin", "net income"
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
            "tolerance", "specification", "CAD", "FEA", "finite element", "torque",
            "tensile strength", "yield strength", "fatigue", "stress analysis",
            "thermodynamics", "kinematics", "dynamics", "fluid mechanics", "hydraulics",
            "pneumatics", "schematic", "blueprint", "prototype", "iteration",
            "commissioning", "decommissioning", "calibration", "compliance",
            "load bearing", "structural integrity", "coefficient", "Reynolds number",
            "Bernoulli", "elasticity", "modulus", "alloy", "composite"
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
            "hypothesis", "methodology", "empirical", "quantitative", "qualitative",
            "peer review", "reproducibility", "statistical significance", "p-value",
            "standard deviation", "control group", "variable", "correlation", "causation",
            "spectroscopy", "chromatography", "centrifuge", "titration", "reagent",
            "catalyst", "substrate", "isotope", "molecule", "polymer", "genome",
            "phenotype", "genotype", "mitochondria", "photosynthesis", "entropy",
            "thermodynamic", "kinetic", "equilibrium", "molar", "molarity"
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
            "KPI", "ROI", "stakeholder", "deliverable", "milestone", "scalability",
            "synergy", "leverage", "bandwidth", "pipeline", "onboarding", "offboarding",
            "quarterly review", "fiscal quarter", "P&L", "bottom line", "top line",
            "year over year", "market share", "competitive advantage", "value proposition",
            "core competency", "strategic initiative", "operational efficiency",
            "change management", "risk mitigation", "due diligence", "SWOT analysis",
            "benchmarking", "SLA", "OKR", "agile", "lean", "Six Sigma"
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
            "conversion rate", "click-through rate", "CTR", "CPA", "CPM", "CPC",
            "lead generation", "lead nurturing", "funnel", "pipeline", "prospect",
            "outreach", "cold call", "warm lead", "qualified lead", "MQL", "SQL",
            "upsell", "cross-sell", "churn rate", "retention", "engagement",
            "brand awareness", "market penetration", "segmentation", "persona",
            "value proposition", "call to action", "A/B testing", "attribution",
            "omnichannel", "content marketing", "SEO", "SEM", "PPC", "ROAS"
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
            "API", "REST", "GraphQL", "microservices", "monolith", "refactor",
            "dependency injection", "singleton", "observer pattern", "MVC", "MVVM",
            "CI/CD", "DevOps", "Kubernetes", "Docker", "containerization",
            "Git", "pull request", "merge conflict", "rebase", "branch",
            "async", "await", "callback", "promise", "closure", "lambda",
            "polymorphism", "inheritance", "encapsulation", "abstraction",
            "stack trace", "debug", "breakpoint", "unit test", "integration test",
            "linting", "transpile", "compile", "runtime", "SDK", "framework",
            "boolean", "integer", "string", "array", "dictionary", "hashmap",
            "algorithm", "binary search", "recursion", "iteration", "OAuth"
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
            "PCB", "printed circuit board", "schematic", "FPGA", "ASIC", "microcontroller",
            "GPIO", "SPI", "I2C", "UART", "USB", "Ethernet", "resistor", "capacitor",
            "inductor", "transistor", "MOSFET", "op-amp", "oscilloscope", "multimeter",
            "voltage regulator", "power supply", "DC-DC converter", "ADC", "DAC",
            "firmware", "embedded", "real-time", "interrupt", "DMA", "clock speed",
            "bandwidth", "impedance", "oscillator", "crystal", "BOM", "footprint",
            "through-hole", "surface mount", "SMD", "soldering", "reflow"
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
            "CNC", "injection molding", "die casting", "extrusion", "stamping",
            "tolerance", "GD&T", "geometric dimensioning", "quality control", "QA",
            "ISO 9001", "lean manufacturing", "Six Sigma", "Kaizen", "5S",
            "bill of materials", "BOM", "work order", "batch", "lot number",
            "first article inspection", "FAI", "SPC", "statistical process control",
            "yield rate", "scrap rate", "cycle time", "takt time", "throughput",
            "OEE", "preventive maintenance", "tooling", "fixture", "jig",
            "heat treatment", "annealing", "tempering", "hardness", "Rockwell"
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
            "RFI", "request for information", "submittal", "change order", "punch list",
            "general contractor", "subcontractor", "superintendent", "foreman",
            "concrete", "rebar", "formwork", "shoring", "excavation", "grading",
            "foundation", "footing", "slab", "framing", "drywall", "HVAC",
            "mechanical", "electrical", "plumbing", "MEP", "structural", "load bearing",
            "building code", "IBC", "ADA", "OSHA", "safety", "PPE",
            "schedule", "critical path", "Gantt chart", "retainage", "lien waiver",
            "bid", "estimate", "scope of work", "specifications", "blueprints",
            "as-built", "shop drawing", "elevation", "section", "detail"
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
            "diagnosis", "prognosis", "etiology", "pathology", "symptom", "syndrome",
            "chronic", "acute", "benign", "malignant", "contraindication", "comorbidity",
            "differential diagnosis", "chief complaint", "history of present illness",
            "review of systems", "physical examination", "assessment", "plan",
            "prescription", "dosage", "milligrams", "intravenous", "subcutaneous",
            "intramuscular", "bilateral", "anterior", "posterior", "lateral", "medial",
            "proximal", "distal", "hypertension", "hypotension", "tachycardia",
            "bradycardia", "edema", "inflammation", "CBC", "BMP", "MRI", "CT scan",
            "EKG", "ECG", "EMR", "EHR", "ICD-10", "CPT", "HIPAA"
        ]
    )

    static let allProfiles: [IndustryProfile] = [
        .general, .legal, .accounting, .engineering, .science,
        .businessManagement, .salesMarketing, .softwareProgramming,
        .hardware, .manufacturing, .construction, .medical
    ]
}
