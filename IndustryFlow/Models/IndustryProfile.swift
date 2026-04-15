import Foundation

/// A common mistranscription pair: what the recognizer typically HEARS
/// vs. the CORRECT term. Fed to Claude during polishing so it knows to
/// fix these specific common errors.
struct CorrectionPair: Codable, Hashable {
    let heard: String
    let correct: String

    init(_ heard: String, _ correct: String) {
        self.heard = heard
        self.correct = correct
    }
}

struct IndustryProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let icon: String
    let systemPrompt: String
    let vocabularyHints: [String]
    var commonMishearings: [CorrectionPair] = []

    /// Custom initializer with default for commonMishearings (backward compat)
    init(id: String, name: String, icon: String, systemPrompt: String,
         vocabularyHints: [String], commonMishearings: [CorrectionPair] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.systemPrompt = systemPrompt
        self.vocabularyHints = vocabularyHints
        self.commonMishearings = commonMishearings
    }

    /// Formatted correction list for inclusion in Claude's system prompt.
    /// Returns empty string if no corrections defined.
    var mishearingsPromptFragment: String {
        guard !commonMishearings.isEmpty else { return "" }

        var lines = ["", "COMMON MISTRANSCRIPTIONS — fix these specific recognizer errors:"]
        for pair in commonMishearings {
            lines.append("- \"\(pair.heard)\" → \"\(pair.correct)\"")
        }
        return lines.joined(separator: "\n")
    }

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
        ],
        commonMishearings: [
            // Latin & legal phrases the recognizer botches
            CorrectionPair("force measure", "force majeure"),
            CorrectionPair("force major", "force majeure"),
            CorrectionPair("force mature", "force majeure"),
            CorrectionPair("voir deer", "voir dire"),
            CorrectionPair("voir dear", "voir dire"),
            CorrectionPair("vore deer", "voir dire"),
            CorrectionPair("res judicata", "res judicata"),
            CorrectionPair("res judacada", "res judicata"),
            CorrectionPair("res judacata", "res judicata"),
            CorrectionPair("rest judicata", "res judicata"),
            CorrectionPair("starry decisis", "stare decisis"),
            CorrectionPair("stare decisis", "stare decisis"),
            CorrectionPair("starey decisis", "stare decisis"),
            CorrectionPair("mens ray", "mens rea"),
            CorrectionPair("mens rea", "mens rea"),
            CorrectionPair("men's rea", "mens rea"),
            CorrectionPair("actos rays", "actus reus"),
            CorrectionPair("actus rays", "actus reus"),
            CorrectionPair("actus rea", "actus reus"),
            CorrectionPair("habias corpus", "habeas corpus"),
            CorrectionPair("habeus corpus", "habeas corpus"),
            CorrectionPair("habeas corpus", "habeas corpus"),
            CorrectionPair("to peena", "subpoena"),
            CorrectionPair("subpena", "subpoena"),
            CorrectionPair("amici curiae", "amicus curiae"),
            CorrectionPair("amicus curiae", "amicus curiae"),
            CorrectionPair("amicas curiae", "amicus curiae"),
            CorrectionPair("pro bo no", "pro bono"),
            CorrectionPair("probono", "pro bono"),
            CorrectionPair("prima fashie", "prima facie"),
            CorrectionPair("prima fasha", "prima facie"),
            CorrectionPair("prima facia", "prima facie"),
            CorrectionPair("a stoppel", "estoppel"),
            CorrectionPair("estopple", "estoppel"),
            CorrectionPair("indemnification", "indemnification"),
            CorrectionPair("in dem nification", "indemnification"),
            CorrectionPair("tort feasor", "tortfeasor"),
            CorrectionPair("tortfeezer", "tortfeasor"),
            CorrectionPair("pro see", "pro se"),
            CorrectionPair("ex party", "ex parte"),
            CorrectionPair("ex partey", "ex parte"),
            CorrectionPair("nolo contend airy", "nolo contendere"),
            CorrectionPair("no lo contend ray", "nolo contendere"),
            CorrectionPair("juris prudence", "jurisprudence"),
            CorrectionPair("jure prudence", "jurisprudence"),
            CorrectionPair("ad hawk", "ad hoc"),
            CorrectionPair("bonafide", "bona fide"),
            CorrectionPair("sui generous", "sui generis"),
            CorrectionPair("ultra veerus", "ultra vires"),
            CorrectionPair("ultra vyrus", "ultra vires"),
            CorrectionPair("caveat empt or", "caveat emptor"),
            CorrectionPair("caveat empty or", "caveat emptor"),
            CorrectionPair("inter alia", "inter alia"),
            CorrectionPair("ipso fact oh", "ipso facto"),
            CorrectionPair("de jury", "de jure"),
            CorrectionPair("de jeery", "de jure"),
            CorrectionPair("the facto", "de facto"),
            CorrectionPair("dee facto", "de facto"),
            CorrectionPair("in cam ra", "in camera"),
            CorrectionPair("demand a mus", "mandamus"),
            CorrectionPair("man damus", "mandamus"),
            CorrectionPair("sir she or rary", "certiorari"),
            CorrectionPair("cert your rary", "certiorari"),
            CorrectionPair("certiorary", "certiorari"),
            CorrectionPair("per claim", "per curiam"),
            CorrectionPair("per cure ee am", "per curiam"),
            CorrectionPair("pellet judge", "appellate judge"),
            CorrectionPair("a pellet judge", "appellate judge"),
            CorrectionPair("a pellet court", "appellate court"),
            CorrectionPair("appel ate", "appellate"),
            CorrectionPair("trespass", "trespass"),
            CorrectionPair("tres pass", "trespass"),
            CorrectionPair("a salt", "assault"),
            CorrectionPair("battery and assault", "assault and battery"),
            CorrectionPair("dee position", "deposition"),
            CorrectionPair("depo nant", "deponent"),
            CorrectionPair("affidavit", "affidavit"),
            CorrectionPair("affy david", "affidavit"),
            CorrectionPair("affidavid", "affidavit"),
            CorrectionPair("interrogator ease", "interrogatories"),
            CorrectionPair("interrog atories", "interrogatories"),
            CorrectionPair("interrogator reese", "interrogatories"),
            CorrectionPair("preponderance", "preponderance"),
            CorrectionPair("prepunder ance", "preponderance"),
            CorrectionPair("punder ance", "preponderance"),
            CorrectionPair("dee fame ation", "defamation"),
            CorrectionPair("def ammatory", "defamatory"),
            CorrectionPair("malicious prosecution", "malicious prosecution"),
            CorrectionPair("malishus prosecution", "malicious prosecution"),
            CorrectionPair("liquidated damage", "liquidated damages"),
            CorrectionPair("liquid ated", "liquidated"),
            CorrectionPair("specific performance", "specific performance"),
            CorrectionPair("hereinafter", "hereinafter"),
            CorrectionPair("here in after", "hereinafter"),
            CorrectionPair("here to fore", "heretofore"),
            CorrectionPair("notwith standing", "notwithstanding"),
            CorrectionPair("not with standing", "notwithstanding"),
            CorrectionPair("there in", "therein"),
            CorrectionPair("where as", "whereas"),
            CorrectionPair("where in", "wherein"),
            CorrectionPair("where to", "whereto")
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
        ],
        commonMishearings: [
            CorrectionPair("gap", "GAAP"),
            CorrectionPair("g a a p", "GAAP"),
            CorrectionPair("eye f r s", "IFRS"),
            CorrectionPair("ifrs", "IFRS"),
            CorrectionPair("sox", "SOX"),
            CorrectionPair("Sarbanes oxley", "Sarbanes-Oxley"),
            CorrectionPair("FASB", "FASB"),
            CorrectionPair("f a s b", "FASB"),
            CorrectionPair("a c p a", "AICPA"),
            CorrectionPair("p c a o b", "PCAOB"),
            CorrectionPair("ASC 606", "ASC 606"),
            CorrectionPair("a s c six oh six", "ASC 606"),
            CorrectionPair("ASC 842", "ASC 842"),
            CorrectionPair("ten K", "10-K"),
            CorrectionPair("ten Q", "10-Q"),
            CorrectionPair("eight K", "8-K"),
            CorrectionPair("ebitda", "EBITDA"),
            CorrectionPair("ee bit duh", "EBITDA"),
            CorrectionPair("ee bit dah", "EBITDA"),
            CorrectionPair("ebit", "EBIT"),
            CorrectionPair("R O I", "ROI"),
            CorrectionPair("R O E", "ROE"),
            CorrectionPair("R O A", "ROA"),
            CorrectionPair("E P S", "EPS"),
            CorrectionPair("p e ratio", "P/E ratio"),
            CorrectionPair("price to earnings", "P/E"),
            CorrectionPair("amortization", "amortization"),
            CorrectionPair("a more tization", "amortization"),
            CorrectionPair("depreciation", "depreciation"),
            CorrectionPair("dee preciation", "depreciation"),
            CorrectionPair("accruel", "accrual"),
            CorrectionPair("accross basis", "accrual basis"),
            CorrectionPair("accounts receivable", "accounts receivable"),
            CorrectionPair("a r", "A/R"),
            CorrectionPair("accounts payable", "accounts payable"),
            CorrectionPair("a p", "A/P"),
            CorrectionPair("g l", "GL"),
            CorrectionPair("general ledger", "general ledger"),
            CorrectionPair("trial balance", "trial balance"),
            CorrectionPair("cogs", "COGS"),
            CorrectionPair("c o g s", "COGS"),
            CorrectionPair("cost of goods sold", "COGS"),
            CorrectionPair("s g and a", "SG&A"),
            CorrectionPair("S G A", "SG&A"),
            CorrectionPair("MRR", "MRR"),
            CorrectionPair("m r r", "MRR"),
            CorrectionPair("ARR", "ARR"),
            CorrectionPair("a r r", "ARR"),
            CorrectionPair("CAC", "CAC"),
            CorrectionPair("cak", "CAC"),
            CorrectionPair("LTV", "LTV"),
            CorrectionPair("l t v", "LTV"),
            CorrectionPair("p and l", "P&L"),
            CorrectionPair("profit and loss", "P&L"),
            CorrectionPair("year over year", "YoY"),
            CorrectionPair("y o y", "YoY"),
            CorrectionPair("quarter over quarter", "QoQ"),
            CorrectionPair("q o q", "QoQ"),
            CorrectionPair("month over month", "MoM"),
            CorrectionPair("cap ex", "CapEx"),
            CorrectionPair("op ex", "OpEx"),
            CorrectionPair("f t e", "FTE"),
            CorrectionPair("full time equivalent", "FTE"),
            CorrectionPair("w 2", "W-2"),
            CorrectionPair("w two", "W-2"),
            CorrectionPair("w 9", "W-9"),
            CorrectionPair("w nine", "W-9"),
            CorrectionPair("ten ninety nine", "1099"),
            CorrectionPair("schedule c", "Schedule C"),
            CorrectionPair("schedule k 1", "Schedule K-1"),
            CorrectionPair("AMT", "AMT"),
            CorrectionPair("a m t", "AMT"),
            CorrectionPair("net operating loss", "NOL"),
            CorrectionPair("n o l", "NOL")
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
            // Electrical (often needed in engineering/construction drawing notes)
            "amp", "amps", "amperes", "volt", "volts", "watt", "kilowatt", "kVA",
            "single phase", "two phase", "three phase",
            "KAIC", "AIC rating", "breaker", "panel", "panelboard", "switchgear",
            "AFCI", "GFCI", "GFI", "RCD", "disconnect", "feeder",
            "gauge", "AWG", "MCM", "kcmil",
            "conduit", "EMT", "PVC", "RMC", "GRC", "flex conduit", "IMC",
            "bus bar", "neutral", "ground", "hot", "phase",
            "#4 AWG", "#6 AWG", "#8 AWG", "#10 AWG", "#12 AWG", "#14 AWG",
            // Process
            "commissioning", "decommissioning", "calibration", "P&ID",
            "ISO", "ASME", "ANSI", "ASTM", "IEEE", "NFPA", "UL", "NEC",
            // Drawing notation
            "on center", "typical", "as shown", "as required", "as noted",
            "per detail", "per plan", "per specification"
        ],
        commonMishearings: [
            // Electrical specs commonly mangled
            CorrectionPair("KIC", "KAIC"),
            CorrectionPair("kayak", "KAIC"),
            CorrectionPair("k a i c", "KAIC"),
            CorrectionPair("kay i c", "KAIC"),
            CorrectionPair("AFC I", "AFCI"),
            CorrectionPair("a f c i", "AFCI"),
            CorrectionPair("GFC I", "GFCI"),
            CorrectionPair("g f c i", "GFCI"),
            CorrectionPair("GFI", "GFCI"),
            CorrectionPair("AWG", "AWG"),
            CorrectionPair("a w g", "AWG"),
            CorrectionPair("MCM", "MCM"),
            CorrectionPair("k c mil", "kcmil"),
            CorrectionPair("two phase", "two-phase"),
            CorrectionPair("three phase", "three-phase"),
            CorrectionPair("single phase", "single-phase"),

            // HVAC abbreviations
            CorrectionPair("BTU", "BTU"),
            CorrectionPair("b t u", "BTU"),
            CorrectionPair("CFM", "CFM"),
            CorrectionPair("c f m", "CFM"),
            CorrectionPair("see fm", "CFM"),
            CorrectionPair("seize them", "CFM"),
            CorrectionPair("SEER", "SEER"),
            CorrectionPair("EER", "EER"),
            CorrectionPair("AFUE", "AFUE"),
            CorrectionPair("a foo", "AFUE"),
            CorrectionPair("delta T", "ΔT"),
            CorrectionPair("delta tea", "ΔT"),
            CorrectionPair("delta P", "ΔP"),
            CorrectionPair("super heat", "superheat"),
            CorrectionPair("sub cooling", "subcooling"),
            CorrectionPair("en thal pee", "enthalpy"),
            CorrectionPair("entropy", "entropy"),

            // Refrigerants
            CorrectionPair("r 410 a", "R-410A"),
            CorrectionPair("r four ten a", "R-410A"),
            CorrectionPair("r 22", "R-22"),
            CorrectionPair("r twenty two", "R-22"),
            CorrectionPair("r 134 a", "R-134A"),

            // Structural
            CorrectionPair("PSI", "PSI"),
            CorrectionPair("p s i", "PSI"),
            CorrectionPair("ribar", "rebar"),
            CorrectionPair("re bar", "rebar"),
            CorrectionPair("I beam", "I-beam"),
            CorrectionPair("eye beam", "I-beam"),
            CorrectionPair("W flange", "W-flange"),
            CorrectionPair("HSS", "HSS"),
            CorrectionPair("h s s", "HSS"),
            CorrectionPair("modulus", "modulus"),
            CorrectionPair("Reynolds number", "Reynolds number"),
            CorrectionPair("renalds number", "Reynolds number"),
            CorrectionPair("burn ooly", "Bernoulli"),
            CorrectionPair("burn newly", "Bernoulli"),
            CorrectionPair("la min are", "laminar"),
            CorrectionPair("turbulent", "turbulent"),

            // Software/CAD
            CorrectionPair("auto cad", "AutoCAD"),
            CorrectionPair("solid works", "SolidWorks"),
            CorrectionPair("cat ee uh", "CATIA"),
            CorrectionPair("re vit", "Revit"),
            CorrectionPair("BIM", "BIM"),
            CorrectionPair("FEA", "FEA"),
            CorrectionPair("CFD", "CFD"),
            CorrectionPair("GD and T", "GD&T"),
            CorrectionPair("g d and t", "GD&T"),
            CorrectionPair("p and i d", "P&ID"),

            // Standards
            CorrectionPair("a s m e", "ASME"),
            CorrectionPair("a n s i", "ANSI"),
            CorrectionPair("a s t m", "ASTM"),
            CorrectionPair("ieee", "IEEE"),
            CorrectionPair("i triple e", "IEEE"),
            CorrectionPair("nfpa", "NFPA"),
            CorrectionPair("n f p a", "NFPA")
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
        ],
        commonMishearings: [
            // Git commands (commonly mangled)
            CorrectionPair("get pull", "git pull"),
            CorrectionPair("get push", "git push"),
            CorrectionPair("get commit", "git commit"),
            CorrectionPair("get merge", "git merge"),
            CorrectionPair("get rebase", "git rebase"),
            CorrectionPair("get clone", "git clone"),
            CorrectionPair("get checkout", "git checkout"),
            CorrectionPair("get branch", "git branch"),
            CorrectionPair("get diff", "git diff"),
            CorrectionPair("get stash", "git stash"),
            CorrectionPair("get log", "git log"),
            CorrectionPair("get reset", "git reset"),
            CorrectionPair("get add", "git add"),
            CorrectionPair("cherry pick", "cherry-pick"),
            CorrectionPair("pull request", "pull request"),
            CorrectionPair("pr review", "PR review"),
            CorrectionPair("merge conflict", "merge conflict"),

            // APIs
            CorrectionPair("a p i", "API"),
            CorrectionPair("rest api", "REST API"),
            CorrectionPair("rust full", "RESTful"),
            CorrectionPair("graph q l", "GraphQL"),
            CorrectionPair("graphical", "GraphQL"),
            CorrectionPair("g r p c", "gRPC"),
            CorrectionPair("web hook", "webhook"),
            CorrectionPair("o auth", "OAuth"),
            CorrectionPair("j w t", "JWT"),
            CorrectionPair("course", "CORS"),

            // Architecture
            CorrectionPair("micro services", "microservices"),
            CorrectionPair("mono lith", "monolith"),
            CorrectionPair("server less", "serverless"),
            CorrectionPair("MVC", "MVC"),
            CorrectionPair("m v c", "MVC"),
            CorrectionPair("MVVM", "MVVM"),
            CorrectionPair("m v v m", "MVVM"),
            CorrectionPair("dependency injection", "dependency injection"),
            CorrectionPair("dee pen den see", "dependency"),
            CorrectionPair("single ton", "singleton"),

            // DevOps
            CorrectionPair("c i c d", "CI/CD"),
            CorrectionPair("CI CD", "CI/CD"),
            CorrectionPair("see i see d", "CI/CD"),
            CorrectionPair("dev ops", "DevOps"),
            CorrectionPair("Kubernet teas", "Kubernetes"),
            CorrectionPair("kuber net teas", "Kubernetes"),
            CorrectionPair("k 8 s", "K8s"),
            CorrectionPair("k eights", "K8s"),
            CorrectionPair("doc er", "Docker"),
            CorrectionPair("doc her", "Docker"),
            CorrectionPair("a w s", "AWS"),
            CorrectionPair("e c 2", "EC2"),
            CorrectionPair("ec two", "EC2"),
            CorrectionPair("s 3", "S3"),
            CorrectionPair("s three", "S3"),
            CorrectionPair("g c p", "GCP"),
            CorrectionPair("terra form", "Terraform"),
            CorrectionPair("engine x", "NGINX"),
            CorrectionPair("nginx", "NGINX"),
            CorrectionPair("c d n", "CDN"),
            CorrectionPair("d n s", "DNS"),

            // Languages & frameworks
            CorrectionPair("Java script", "JavaScript"),
            CorrectionPair("type script", "TypeScript"),
            CorrectionPair("py thon", "Python"),
            CorrectionPair("c plus plus", "C++"),
            CorrectionPair("c sharp", "C#"),
            CorrectionPair("dot net", ".NET"),
            CorrectionPair("react js", "React"),
            CorrectionPair("react", "React"),
            CorrectionPair("v u", "Vue"),
            CorrectionPair("vu jay s", "Vue.js"),
            CorrectionPair("note js", "Node.js"),
            CorrectionPair("node js", "Node.js"),
            CorrectionPair("n p m", "npm"),
            CorrectionPair("yarn", "yarn"),
            CorrectionPair("pip", "pip"),

            // Databases
            CorrectionPair("post grass", "PostgreSQL"),
            CorrectionPair("post gress", "PostgreSQL"),
            CorrectionPair("post gres", "PostgreSQL"),
            CorrectionPair("my sequel", "MySQL"),
            CorrectionPair("my s q l", "MySQL"),
            CorrectionPair("mongo D B", "MongoDB"),
            CorrectionPair("mongo db", "MongoDB"),
            CorrectionPair("red is", "Redis"),
            CorrectionPair("sequel light", "SQLite"),
            CorrectionPair("no sequel", "NoSQL"),

            // Code concepts
            CorrectionPair("a sing", "async"),
            CorrectionPair("a wait", "await"),
            CorrectionPair("call back", "callback"),
            CorrectionPair("prom is", "Promise"),
            CorrectionPair("clo sure", "closure"),
            CorrectionPair("lambda function", "lambda function"),
            CorrectionPair("local host", "localhost"),
            CorrectionPair("end point", "endpoint"),
            CorrectionPair("front end", "frontend"),
            CorrectionPair("back end", "backend"),
            CorrectionPair("full stack", "full-stack"),
            CorrectionPair("hash map", "hashmap"),
            CorrectionPair("regex", "regex"),
            CorrectionPair("reg x", "regex"),

            // Process
            CorrectionPair("stand up", "standup"),
            CorrectionPair("retro spective", "retrospective"),
            CorrectionPair("kan ban", "kanban"),
            CorrectionPair("scrum master", "scrum master"),
            CorrectionPair("user story", "user story"),
            CorrectionPair("story points", "story points"),
            CorrectionPair("burn down", "burndown"),
            CorrectionPair("epic", "epic"),
            CorrectionPair("Jira", "Jira"),
            CorrectionPair("hera", "Jira"),
            CorrectionPair("github", "GitHub"),
            CorrectionPair("git hub", "GitHub")
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
            "Primavera", "P6", "Procore", "Bluebeam", "PlanGrid",
            // Electrical terms (for drawing notes)
            "amp", "amps", "volt", "volts", "kVA", "KAIC", "breaker", "panel",
            "single phase", "two phase", "three phase", "AFCI", "GFCI",
            "gauge", "AWG", "conduit", "EMT", "PVC", "RMC",
            "#12 AWG", "#10 AWG", "#8 AWG", "#6 AWG", "#4 AWG",
            // Drawing notation shorthand
            "typical", "on center", "O.C.", "T.Y.P.", "TYP",
            "as shown", "as noted", "as required", "per plan", "per detail",
            "approximately", "APPROX", "maximum", "MAX", "minimum", "MIN",
            "required", "reference", "equal", "EQ"
        ],
        commonMishearings: [
            // Project documents
            CorrectionPair("RFI", "RFI"),
            CorrectionPair("r f i", "RFI"),
            CorrectionPair("our f i", "RFI"),
            CorrectionPair("change order", "change order"),
            CorrectionPair("punch list", "punch list"),
            CorrectionPair("submittal", "submittal"),
            CorrectionPair("sub midal", "submittal"),
            CorrectionPair("substantial completion", "substantial completion"),
            CorrectionPair("notice to proceed", "notice to proceed"),
            CorrectionPair("NTP", "NTP"),
            CorrectionPair("certificate of occupancy", "certificate of occupancy"),
            CorrectionPair("as built", "as-built"),
            CorrectionPair("shop drawing", "shop drawing"),

            // Contracts
            CorrectionPair("GMP", "GMP"),
            CorrectionPair("g m p", "GMP"),
            CorrectionPair("guaranteed maximum price", "guaranteed maximum price"),
            CorrectionPair("AIA", "AIA"),
            CorrectionPair("a i a", "AIA"),
            CorrectionPair("Davis Bacon", "Davis-Bacon"),
            CorrectionPair("davis bacon", "Davis-Bacon"),
            CorrectionPair("retainage", "retainage"),
            CorrectionPair("re tay nage", "retainage"),
            CorrectionPair("lien waiver", "lien waiver"),
            CorrectionPair("lean waiver", "lien waiver"),

            // Roles
            CorrectionPair("super in tendant", "superintendent"),
            CorrectionPair("super intendant", "superintendent"),
            CorrectionPair("for man", "foreman"),
            CorrectionPair("subcontractor", "subcontractor"),
            CorrectionPair("sub contractor", "subcontractor"),

            // Structural / site
            CorrectionPair("ribar", "rebar"),
            CorrectionPair("re bar", "rebar"),
            CorrectionPair("form work", "formwork"),
            CorrectionPair("foundation", "foundation"),
            CorrectionPair("footing", "footing"),
            CorrectionPair("caisson", "caisson"),
            CorrectionPair("kay son", "caisson"),
            CorrectionPair("cay son", "caisson"),
            CorrectionPair("post tension", "post-tensioned"),
            CorrectionPair("post tensioned", "post-tensioned"),
            CorrectionPair("til tup", "tilt-up"),
            CorrectionPair("tilt up", "tilt-up"),
            CorrectionPair("pre cast", "precast"),
            CorrectionPair("slab on grade", "slab on grade"),
            CorrectionPair("grade beam", "grade beam"),
            CorrectionPair("framing", "framing"),
            CorrectionPair("joist", "joist"),
            CorrectionPair("joyst", "joist"),
            CorrectionPair("truss", "truss"),

            // Trades & systems
            CorrectionPair("HVAC", "HVAC"),
            CorrectionPair("h v a c", "HVAC"),
            CorrectionPair("MEP", "MEP"),
            CorrectionPair("m e p", "MEP"),
            CorrectionPair("me ep", "MEP"),

            // Codes
            CorrectionPair("IBC", "IBC"),
            CorrectionPair("i b c", "IBC"),
            CorrectionPair("IRC", "IRC"),
            CorrectionPair("i r c", "IRC"),
            CorrectionPair("NEC", "NEC"),
            CorrectionPair("n e c", "NEC"),
            CorrectionPair("OSHA", "OSHA"),
            CorrectionPair("oh shah", "OSHA"),
            CorrectionPair("LEED", "LEED"),
            CorrectionPair("lead certification", "LEED certification"),

            // Drawing notation
            CorrectionPair("on center", "O.C."),
            CorrectionPair("oh see", "O.C."),
            CorrectionPair("typical", "TYP."),
            CorrectionPair("approximately", "APPROX."),
            CorrectionPair("maximum", "MAX."),
            CorrectionPair("minimum", "MIN."),
            CorrectionPair("required", "REQ'D"),

            // Electrical (often comes up in construction notes)
            CorrectionPair("KIC", "KAIC"),
            CorrectionPair("kayak", "KAIC"),
            CorrectionPair("AFC I", "AFCI"),
            CorrectionPair("GFC I", "GFCI"),
            CorrectionPair("GFI", "GFCI"),
            CorrectionPair("two phase", "two-phase"),
            CorrectionPair("three phase", "three-phase"),
            CorrectionPair("single phase", "single-phase")
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
        ],
        commonMishearings: [
            // Symptoms & conditions
            CorrectionPair("disp nia", "dyspnea"),
            CorrectionPair("disney uh", "dyspnea"),
            CorrectionPair("disp neeyuh", "dyspnea"),
            CorrectionPair("attack a cardia", "tachycardia"),
            CorrectionPair("attacky cardia", "tachycardia"),
            CorrectionPair("brody cardia", "bradycardia"),
            CorrectionPair("broody cardia", "bradycardia"),
            CorrectionPair("hyper tense ion", "hypertension"),
            CorrectionPair("hyper tension", "hypertension"),
            CorrectionPair("hi pot tense ion", "hypotension"),
            CorrectionPair("hypo tension", "hypotension"),
            CorrectionPair("a dema", "edema"),
            CorrectionPair("ed em uh", "edema"),
            CorrectionPair("inflame nation", "inflammation"),
            CorrectionPair("inflam nation", "inflammation"),
            CorrectionPair("comb worbid", "comorbid"),
            CorrectionPair("co morbid", "comorbid"),
            CorrectionPair("co morbidity", "comorbidity"),
            CorrectionPair("contra indication", "contraindication"),
            CorrectionPair("contra dictation", "contraindication"),
            CorrectionPair("ano fee laxes", "anaphylaxis"),
            CorrectionPair("ana fill axes", "anaphylaxis"),
            CorrectionPair("assist tom attic", "asymptomatic"),
            CorrectionPair("a simp tomatic", "asymptomatic"),
            CorrectionPair("idio path ic", "idiopathic"),
            CorrectionPair("eye dee opathic", "idiopathic"),
            CorrectionPair("eye attic genic", "iatrogenic"),
            CorrectionPair("ataru genic", "iatrogenic"),
            CorrectionPair("etiology", "etiology"),
            CorrectionPair("eat ee ology", "etiology"),
            CorrectionPair("ah cute", "acute"),
            CorrectionPair("malig nant", "malignant"),
            CorrectionPair("be nine", "benign"),
            CorrectionPair("met astatic", "metastatic"),
            CorrectionPair("meta static", "metastatic"),

            // Anatomy & positioning
            CorrectionPair("by lateral", "bilateral"),
            CorrectionPair("you knee lateral", "unilateral"),
            CorrectionPair("anti error", "anterior"),
            CorrectionPair("post air ee or", "posterior"),
            CorrectionPair("medial", "medial"),
            CorrectionPair("dorsel", "dorsal"),
            CorrectionPair("ventrul", "ventral"),
            CorrectionPair("supine", "supine"),
            CorrectionPair("sup pine", "supine"),
            CorrectionPair("prone position", "prone"),
            CorrectionPair("contra lateral", "contralateral"),
            CorrectionPair("ipsy lateral", "ipsilateral"),
            CorrectionPair("ipsi lateral", "ipsilateral"),
            CorrectionPair("subq", "SubQ"),
            CorrectionPair("sub Q", "SubQ"),
            CorrectionPair("sub cutaneous", "subcutaneous"),
            CorrectionPair("intra venous", "intravenous"),
            CorrectionPair("intra muscular", "intramuscular"),

            // Vital signs / labs
            CorrectionPair("trope onin", "troponin"),
            CorrectionPair("tropo nin", "troponin"),
            CorrectionPair("creatin in", "creatinine"),
            CorrectionPair("creatin een", "creatinine"),
            CorrectionPair("hemoglobin a one c", "HbA1c"),
            CorrectionPair("hemoglobin a 1c", "HbA1c"),
            CorrectionPair("HBA1C", "HbA1c"),
            CorrectionPair("hep uh", "HIPAA"),
            CorrectionPair("hippo", "HIPAA"),
            CorrectionPair("HEPA", "HIPAA"),
            CorrectionPair("hippa", "HIPAA"),
            CorrectionPair("ICD 10", "ICD-10"),
            CorrectionPair("I C D 10", "ICD-10"),
            CorrectionPair("ICD ten", "ICD-10"),
            CorrectionPair("MRI", "MRI"),
            CorrectionPair("M R I", "MRI"),
            CorrectionPair("CT scan", "CT scan"),
            CorrectionPair("C T scan", "CT scan"),
            CorrectionPair("EKG", "EKG"),
            CorrectionPair("E K G", "EKG"),
            CorrectionPair("ECG", "ECG"),
            CorrectionPair("E C G", "ECG"),
            CorrectionPair("echo cardiogram", "echocardiogram"),

            // Medication frequency abbreviations
            CorrectionPair("be id", "BID"),
            CorrectionPair("bid medication", "BID medication"),
            CorrectionPair("tid medication", "TID medication"),
            CorrectionPair("queue id", "QID"),
            CorrectionPair("queue HS", "QHS"),
            CorrectionPair("queue h s", "QHS"),
            CorrectionPair("PRN", "PRN"),
            CorrectionPair("perm", "PRN"),
            CorrectionPair("p o", "PO"),
            CorrectionPair("by mouth", "PO"),

            // Documentation acronyms
            CorrectionPair("soap note", "SOAP note"),
            CorrectionPair("s o a p note", "SOAP note"),
            CorrectionPair("HPI", "HPI"),
            CorrectionPair("h p i", "HPI"),
            CorrectionPair("history of present illness", "HPI"),
            CorrectionPair("ROS", "ROS"),
            CorrectionPair("review of systems", "ROS"),
            CorrectionPair("DDX", "DDx"),
            CorrectionPair("d d x", "DDx"),
            CorrectionPair("differential diagnosis", "DDx"),
            CorrectionPair("a and p", "A&P"),
            CorrectionPair("assessment and plan", "A&P"),
            CorrectionPair("CC", "CC"),
            CorrectionPair("chief complaint", "chief complaint"),
            CorrectionPair("EMR", "EMR"),
            CorrectionPair("EHR", "EHR"),
            CorrectionPair("e m r", "EMR"),
            CorrectionPair("e h r", "EHR")
        ]
    )

    static let allProfiles: [IndustryProfile] = [
        .general, .legal, .accounting, .engineering, .science,
        .businessManagement, .salesMarketing, .softwareProgramming,
        .hardware, .manufacturing, .construction, .medical
    ]
}
