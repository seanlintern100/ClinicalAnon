"""
Presidio Engine - Wrapper for Microsoft Presidio PII detection

Provides vanilla Presidio detection for comparison.
"""

from typing import List
from dataclasses import dataclass

from presidio_analyzer import AnalyzerEngine
from presidio_analyzer.nlp_engine import NlpEngineProvider


@dataclass
class DetectedEntity:
    """Represents a detected PII entity"""
    text: str
    entity_type: str
    start: int
    end: int
    confidence: float
    source: str = "presidio"


class PresidioEngine:
    """
    Vanilla Microsoft Presidio PII detection.
    Uses default recognizers without NZ-specific patterns.
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

        # Entity types to detect
        self.entities = [
            "PERSON",
            "LOCATION",
            "PHONE_NUMBER",
            "EMAIL_ADDRESS",
            "DATE_TIME",
            "CREDIT_CARD",
            "CRYPTO",
            "IBAN_CODE",
            "IP_ADDRESS",
            "MEDICAL_LICENSE",
            "URL",
            "NRP",  # Nationality, Religious, Political group
        ]

    def detect(self, text: str) -> List[DetectedEntity]:
        """Detect PII entities using Presidio"""
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
                source="presidio"
            ))

        return entities
