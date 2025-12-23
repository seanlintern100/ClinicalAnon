"""
Presidio NZ Engine - Presidio with NZ-specific recognizers

Extends Presidio with custom recognizers for:
- NZ NHI numbers
- NZ phone formats
- Auckland suburbs
- Maori names
"""

from typing import List
from dataclasses import dataclass

from presidio_analyzer import AnalyzerEngine, Pattern, PatternRecognizer
from presidio_analyzer.nlp_engine import NlpEngineProvider


@dataclass
class DetectedEntity:
    """Represents a detected PII entity"""
    text: str
    entity_type: str
    start: int
    end: int
    confidence: float
    source: str = "presidio_nz"


class NZNHIRecognizer(PatternRecognizer):
    """Recognizes NZ National Health Index (NHI) numbers"""

    def __init__(self):
        patterns = [
            Pattern(
                name="nhi_pattern",
                regex=r"\b[A-Z]{3}\d{4}\b",
                score=0.85
            )
        ]
        super().__init__(
            supported_entity="NZ_NHI",
            patterns=patterns,
            context=["nhi", "national health index", "health number"]
        )


class NZACCRecognizer(PatternRecognizer):
    """Recognizes NZ ACC case numbers"""

    def __init__(self):
        patterns = [
            Pattern(
                name="acc_pattern",
                regex=r"\bACC\s?\d{5,}\b",
                score=0.9
            )
        ]
        super().__init__(
            supported_entity="NZ_ACC",
            patterns=patterns,
            context=["acc", "accident", "compensation", "claim"]
        )


class NZPhoneRecognizer(PatternRecognizer):
    """Recognizes NZ phone number formats"""

    def __init__(self):
        patterns = [
            # NZ Mobile: 021/022/027/029
            Pattern(
                name="nz_mobile",
                regex=r"\b0(21|22|27|29)[\s-]?\d{3}[\s-]?\d{4}\b",
                score=0.95
            ),
            # NZ Landline: 03-09
            Pattern(
                name="nz_landline",
                regex=r"\b0[3-9][\s-]?\d{3}[\s-]?\d{4}\b",
                score=0.9
            ),
            # International +64
            Pattern(
                name="nz_international",
                regex=r"\+64[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}\b",
                score=0.95
            ),
            # 0800 freephone
            Pattern(
                name="nz_freephone",
                regex=r"\b0800[\s-]?\d{3}[\s-]?\d{3}\b",
                score=0.9
            ),
        ]
        super().__init__(
            supported_entity="NZ_PHONE",
            patterns=patterns,
            context=["phone", "mobile", "contact", "call", "ring"]
        )


class NZLocationRecognizer(PatternRecognizer):
    """Recognizes NZ-specific locations"""

    def __init__(self):
        patterns = [
            # Auckland suburbs
            Pattern(
                name="auckland_suburbs",
                regex=r"\b(?:Otahuhu|Manukau|Papatoetoe|Mangere|Mt Eden|Ponsonby|Parnell|Remuera|Epsom|Newmarket|Grey Lynn|Avondale|New Lynn|Henderson|Albany|Takapuna|Devonport|Ellerslie|Panmure|Howick|Pakuranga|Botany|Flat Bush)\b",
                score=0.95
            ),
            # NZ cities
            Pattern(
                name="nz_cities",
                regex=r"\b(?:Auckland|Wellington|Christchurch|Dunedin|Hamilton|Tauranga|Napier|Hastings|Palmerston North|Rotorua|Nelson|Queenstown|Invercargill|Whangarei)\b",
                score=0.85  # Lower score - could be legitimate references
            ),
            # NZ Hospitals
            Pattern(
                name="nz_hospitals",
                regex=r"\b(?:Auckland|Middlemore|North Shore|Waitakere|Starship|Greenlane|Wellington|Hutt|Christchurch|Dunedin)\s+Hospital\b",
                score=0.95
            ),
            # Street addresses
            Pattern(
                name="street_address",
                regex=r"\d+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Road|Street|Terrace|Avenue|Drive|Lane|Place|Crescent|Way|Grove|Close|Court)\b",
                score=0.9
            ),
        ]
        super().__init__(
            supported_entity="NZ_LOCATION",
            patterns=patterns,
            context=["address", "location", "suburb", "city", "hospital"]
        )


class NZDHBRecognizer(PatternRecognizer):
    """Recognizes NZ District Health Boards"""

    def __init__(self):
        patterns = [
            Pattern(
                name="dhb_pattern",
                regex=r"\b(?:Auckland|Waitemata|Counties Manukau|Canterbury|Southern|Capital & Coast|Hutt Valley)\s+(?:DHB|District Health Board|Clinic)\b",
                score=0.9
            )
        ]
        super().__init__(
            supported_entity="NZ_DHB",
            patterns=patterns,
            context=["dhb", "health board", "district"]
        )


class MaoriNameRecognizer(PatternRecognizer):
    """Recognizes Maori names using dictionary and phonetic patterns"""

    def __init__(self):
        # Build regex for known Maori names
        first_names = [
            "Wiremu", "Hemi", "Pita", "Rawiri", "Mikaere", "Tane", "Rangi",
            "Tamati", "Hohepa", "Aperahama", "Timoti", "Hone", "Paora",
            "Aroha", "Kiri", "Mere", "Hana", "Anahera", "Moana", "Ngaire",
            "Whetu", "Kahu", "Ataahua", "Hinewai", "Hine", "Marama", "Ariana"
        ]
        names_pattern = "|".join(first_names)

        patterns = [
            # Known Maori names (dictionary)
            Pattern(
                name="maori_names",
                regex=rf"\b(?:{names_pattern})\b",
                score=0.95
            ),
            # Phonetic patterns (wh, ng clusters)
            Pattern(
                name="maori_phonetic",
                regex=r"\b[A-Z][a-z]*(?:wh|ng)[a-z]+\b",
                score=0.6
            ),
        ]
        super().__init__(
            supported_entity="MAORI_NAME",
            patterns=patterns,
            context=["name", "client", "patient", "person", "whanau"]
        )


class PresidioNZEngine:
    """
    Microsoft Presidio with NZ-specific recognizers added.
    """

    def __init__(self):
        # Configure spaCy NLP engine
        configuration = {
            "nlp_engine_name": "spacy",
            "models": [{"lang_code": "en", "model_name": "en_core_web_lg"}],
        }

        provider = NlpEngineProvider(nlp_configuration=configuration)
        nlp_engine = provider.create_engine()

        # Create analyzer with default recognizers
        self.analyzer = AnalyzerEngine(nlp_engine=nlp_engine)

        # Add NZ-specific recognizers
        self.analyzer.registry.add_recognizer(NZNHIRecognizer())
        self.analyzer.registry.add_recognizer(NZACCRecognizer())
        self.analyzer.registry.add_recognizer(NZPhoneRecognizer())
        self.analyzer.registry.add_recognizer(NZLocationRecognizer())
        self.analyzer.registry.add_recognizer(NZDHBRecognizer())
        self.analyzer.registry.add_recognizer(MaoriNameRecognizer())

        # Entity types to detect (default + NZ-specific)
        self.entities = [
            # Default Presidio entities
            "PERSON",
            "LOCATION",
            "PHONE_NUMBER",
            "EMAIL_ADDRESS",
            "DATE_TIME",
            "CREDIT_CARD",
            "URL",
            # NZ-specific entities
            "NZ_NHI",
            "NZ_ACC",
            "NZ_PHONE",
            "NZ_LOCATION",
            "NZ_DHB",
            "MAORI_NAME",
        ]

    def detect(self, text: str) -> List[DetectedEntity]:
        """Detect PII entities using Presidio + NZ recognizers"""
        results = self.analyzer.analyze(
            text=text,
            entities=self.entities,
            language="en"
        )

        entities = []
        for result in results:
            entities.append(DetectedEntity(
                text=text[result.start:result.end],
                entity_type=result.entity_type,
                start=result.start,
                end=result.end,
                confidence=result.score,
                source="presidio_nz"
            ))

        return entities
