"""
Current Engine - Python port of the Swift-based PII detection patterns

This replicates the detection logic from the ClinicalAnon Swift app
to enable fair comparison with Presidio.
"""

import re
import spacy
from dataclasses import dataclass, field
from typing import List, Tuple, Set
from enum import Enum


class EntityType(Enum):
    PERSON = "PERSON"
    PERSON_CLIENT = "PERSON_CLIENT"
    PERSON_PROVIDER = "PERSON_PROVIDER"
    PERSON_OTHER = "PERSON_OTHER"
    DATE = "DATE"
    LOCATION = "LOCATION"
    ORGANIZATION = "ORGANIZATION"
    IDENTIFIER = "IDENTIFIER"
    CONTACT = "CONTACT"


@dataclass
class DetectedEntity:
    """Represents a detected PII entity"""
    text: str
    entity_type: EntityType
    start: int
    end: int
    confidence: float
    source: str = "current"  # Which engine detected it


class CurrentEngine:
    """
    Python port of the Swift ClinicalAnon detection patterns.
    Uses spaCy for NER (equivalent to Apple NER) plus custom regex patterns.
    """

    def __init__(self):
        # Load spaCy model (equivalent to Apple's NaturalLanguage NER)
        try:
            self.nlp = spacy.load("en_core_web_lg")
        except OSError:
            print("WARNING: en_core_web_lg not found. Run: python -m spacy download en_core_web_lg")
            self.nlp = None

        # Common words to exclude (from Swift isCommonWord)
        self.common_words: Set[str] = {
            # Articles
            "the", "a", "an",
            # Conjunctions
            "and", "but", "or", "nor", "for", "yet", "so",
            # Prepositions
            "in", "on", "at", "to", "from", "with", "by", "of", "about",
            # Pronouns
            "he", "she", "it", "they", "we", "you", "i",
            "him", "her", "them", "us", "me",
            "his", "its", "their", "our", "your", "my",
            # Common verbs
            "is", "was", "are", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did",
            # Other common words
            "this", "that", "these", "those",
            "when", "where", "what", "which", "who", "why", "how",
            # Medical/clinical common words
            "patient", "treatment", "therapy", "care", "health",
            "medical", "clinical", "hospital", "clinic", "doctor",
            # Relationship words
            "mother", "father", "sister", "brother", "son", "daughter",
            "wife", "husband", "partner", "friend", "family", "whanau"
        }

        # Maori names dictionary (from MaoriNameRecognizer.swift)
        self.maori_first_names: Set[str] = {
            # Male names
            "Wiremu", "Hemi", "Pita", "Rawiri", "Mikaere", "Tane", "Rangi",
            "Tamati", "Hohepa", "Aperahama", "Timoti", "Hone", "Paora",
            # Female names
            "Aroha", "Kiri", "Mere", "Hana", "Anahera", "Moana", "Ngaire",
            "Whetu", "Kahu", "Ataahua", "Hinewai", "Hine", "Marama", "Ariana",
        }

        self.maori_last_names: Set[str] = {
            "Ngata", "Te Ao", "Tawhiri", "Wairua", "Takiri",
            "Parata", "Ngati", "Whaanga", "Eruera"
        }

        # Relationship words (from RelationshipNameExtractor.swift)
        self.relationship_words: Set[str] = {
            # Family relationships
            "mother", "father", "sister", "brother", "son", "daughter",
            "grandmother", "grandfather", "grandma", "grandpa",
            "aunt", "uncle", "cousin", "niece", "nephew",
            "stepmother", "stepfather", "stepsister", "stepbrother",
            # Maori/cultural terms
            "whanau", "whangai",
            # Partnerships
            "wife", "husband", "partner", "spouse", "fiance", "fiancee",
            "boyfriend", "girlfriend", "ex-wife", "ex-husband",
            # Social relationships
            "friend", "flatmate", "roommate", "colleague", "coworker",
            "neighbor", "neighbour", "mate", "buddy"
        }

        # Maori phonetic false positives (from MaoriNameRecognizer.swift)
        self.maori_false_positives: Set[str] = {
            "Where", "When", "What", "Thing", "Something", "Anything",
            "Whither", "Whether", "Whence"
        }

    def detect(self, text: str) -> List[DetectedEntity]:
        """Run all recognizers and return detected entities"""
        entities = []

        # 1. spaCy NER (equivalent to AppleNERRecognizer)
        entities.extend(self._spacy_ner(text))

        # 2. Maori names (MaoriNameRecognizer)
        entities.extend(self._maori_names(text))

        # 3. Relationship name extraction (RelationshipNameExtractor)
        entities.extend(self._relationship_names(text))

        # 4. NZ Phone numbers (NZPhoneRecognizer)
        entities.extend(self._nz_phones(text))

        # 5. NZ Medical IDs (NZMedicalIDRecognizer)
        entities.extend(self._nz_medical_ids(text))

        # 6. NZ Addresses (NZAddressRecognizer)
        entities.extend(self._nz_addresses(text))

        # 7. Dates (DateRecognizer)
        entities.extend(self._dates(text))

        # Remove overlaps and deduplicate
        entities = self._remove_overlaps(entities)
        entities = self._deduplicate(entities)

        return entities

    def _spacy_ner(self, text: str) -> List[DetectedEntity]:
        """Use spaCy NER - equivalent to AppleNERRecognizer"""
        if not self.nlp:
            return []

        entities = []
        doc = self.nlp(text)

        for ent in doc.ents:
            # Skip common words
            if ent.text.lower() in self.common_words:
                continue

            # Map spaCy labels to our types
            if ent.label_ == "PERSON":
                entity_type = EntityType.PERSON_OTHER
            elif ent.label_ in ("GPE", "LOC"):
                entity_type = EntityType.LOCATION
            elif ent.label_ == "ORG":
                entity_type = EntityType.ORGANIZATION
            else:
                continue  # Skip other types

            entities.append(DetectedEntity(
                text=ent.text,
                entity_type=entity_type,
                start=ent.start_char,
                end=ent.end_char,
                confidence=0.7,  # Apple NER baseline
                source="current_spacy"
            ))

        return entities

    def _maori_names(self, text: str) -> List[DetectedEntity]:
        """Detect Maori names - dictionary + phonetic patterns"""
        entities = []

        # Dictionary lookup
        words = text.split()
        current_pos = 0

        for word in words:
            clean_word = word.strip(".,;:!?\"'()")
            if clean_word in self.maori_first_names or clean_word in self.maori_last_names:
                # Find position in text
                match = re.search(re.escape(clean_word), text[current_pos:])
                if match:
                    start = current_pos + match.start()
                    end = current_pos + match.end()
                    entities.append(DetectedEntity(
                        text=clean_word,
                        entity_type=EntityType.PERSON_OTHER,
                        start=start,
                        end=end,
                        confidence=0.95,
                        source="current_maori_dict"
                    ))
            current_pos = text.find(word, current_pos) + len(word)

        # Phonetic pattern matching
        maori_pattern = r"\b[A-Z][a-z]*(?:wh|ng)[a-z]+|\b[A-Z][aeiouAEIOU]{2,}[a-z]*\b"
        for match in re.finditer(maori_pattern, text):
            word = match.group()
            # Skip false positives
            if word in self.maori_false_positives:
                continue
            # Skip if already in dictionary
            if word in self.maori_first_names or word in self.maori_last_names:
                continue

            entities.append(DetectedEntity(
                text=word,
                entity_type=EntityType.PERSON_OTHER,
                start=match.start(),
                end=match.end(),
                confidence=0.6,
                source="current_maori_phonetic"
            ))

        return entities

    def _relationship_names(self, text: str) -> List[DetectedEntity]:
        """Extract names after relationship words"""
        entities = []

        for relationship in self.relationship_words:
            # Pattern: relationship word + capitalized name(s)
            pattern = rf"\b{relationship}\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)?)"
            for match in re.finditer(pattern, text, re.IGNORECASE):
                name = match.group(1)
                if name.lower() not in self.common_words:
                    # Get position of the name (not the relationship word)
                    name_start = match.start(1)
                    name_end = match.end(1)
                    entities.append(DetectedEntity(
                        text=name,
                        entity_type=EntityType.PERSON_OTHER,
                        start=name_start,
                        end=name_end,
                        confidence=0.9,
                        source="current_relationship"
                    ))

        return entities

    def _nz_phones(self, text: str) -> List[DetectedEntity]:
        """Detect NZ phone numbers"""
        patterns = [
            # NZ Mobile: 021/022/027/029
            (r"\b0(21|22|27|29)[\s-]?\d{3}[\s-]?\d{4}\b", 0.95),
            # NZ Landline: 03-09
            (r"\b0[3-9][\s-]?\d{3}[\s-]?\d{4}\b", 0.9),
            # International +64
            (r"\+64[\s-]?\d{1,2}[\s-]?\d{3}[\s-]?\d{4}\b", 0.95),
            # 0800 freephone
            (r"\b0800[\s-]?\d{3}[\s-]?\d{3}\b", 0.9),
        ]

        return self._pattern_match(text, patterns, EntityType.CONTACT, "current_phone")

    def _nz_medical_ids(self, text: str) -> List[DetectedEntity]:
        """Detect NZ medical identifiers (NHI, ACC, etc.)"""
        patterns = [
            # NHI: 3 letters + 4 digits
            (r"\b[A-Z]{3}\d{4}\b", 0.85),
            # ACC case numbers
            (r"\bACC\s?\d{5,}\b", 0.9),
            # Generic MRN/Case/ID
            (r"\b(?:MRN|Case|ID)\s*[:#]?\s*[A-Z0-9-]{4,}\b", 0.8),
            # Medical record with prefix
            (r"\b(?:MR|CR|UR)-\d{5,}\b", 0.85),
        ]

        return self._pattern_match(text, patterns, EntityType.IDENTIFIER, "current_medical_id")

    def _nz_addresses(self, text: str) -> List[DetectedEntity]:
        """Detect NZ addresses and locations"""
        entities = []

        # Street addresses
        street_pattern = r"\d+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\s+(?:Road|Street|Terrace|Avenue|Drive|Lane|Place|Crescent|Way|Grove|Close|Court)\b"
        for match in re.finditer(street_pattern, text):
            entities.append(DetectedEntity(
                text=match.group(),
                entity_type=EntityType.LOCATION,
                start=match.start(),
                end=match.end(),
                confidence=0.9,
                source="current_address"
            ))

        # Auckland suburbs
        suburbs = r"\b(?:Otahuhu|Manukau|Papatoetoe|Mangere|Mt Eden|Ponsonby|Parnell|Remuera|Epsom|Newmarket|Grey Lynn|Avondale|New Lynn|Henderson|Albany|Takapuna|Devonport|Ellerslie|Panmure|Howick|Pakuranga|Botany|Flat Bush)\b"
        for match in re.finditer(suburbs, text):
            entities.append(DetectedEntity(
                text=match.group(),
                entity_type=EntityType.LOCATION,
                start=match.start(),
                end=match.end(),
                confidence=0.95,
                source="current_suburb"
            ))

        # NZ cities
        cities = r"\b(?:Wellington|Christchurch|Dunedin|Hamilton|Tauranga|Napier|Hastings|Palmerston North|Rotorua|Nelson|Queenstown|Invercargill|Whangarei)\b"
        for match in re.finditer(cities, text):
            entities.append(DetectedEntity(
                text=match.group(),
                entity_type=EntityType.LOCATION,
                start=match.start(),
                end=match.end(),
                confidence=0.95,
                source="current_city"
            ))

        # NZ Hospitals
        hospitals = r"\b(?:Auckland|Middlemore|North Shore|Waitakere|Starship|Greenlane|Wellington|Hutt|Christchurch|Dunedin)\s+Hospital\b"
        for match in re.finditer(hospitals, text):
            entities.append(DetectedEntity(
                text=match.group(),
                entity_type=EntityType.LOCATION,
                start=match.start(),
                end=match.end(),
                confidence=0.95,
                source="current_hospital"
            ))

        # DHBs
        dhbs = r"\b(?:Auckland|Waitemata|Counties Manukau|Canterbury|Southern|Capital & Coast|Hutt Valley)\s+(?:DHB|District Health Board|Clinic)\b"
        for match in re.finditer(dhbs, text):
            entities.append(DetectedEntity(
                text=match.group(),
                entity_type=EntityType.ORGANIZATION,
                start=match.start(),
                end=match.end(),
                confidence=0.9,
                source="current_dhb"
            ))

        return entities

    def _dates(self, text: str) -> List[DetectedEntity]:
        """Detect dates in various formats"""
        patterns = [
            # DD/MM/YYYY
            (r"\b\d{1,2}/\d{1,2}/\d{4}\b", 0.95),
            # DD-MM-YYYY
            (r"\b\d{1,2}-\d{1,2}-\d{4}\b", 0.95),
            # YYYY-MM-DD (ISO)
            (r"\b\d{4}-\d{1,2}-\d{1,2}\b", 0.95),
            # Month DD, YYYY
            (r"\b(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{1,2},?\s+\d{4}\b", 0.95),
            # DD Month YYYY
            (r"\b\d{1,2}\s+(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b", 0.95),
            # DD Mon YYYY
            (r"\b\d{1,2}\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b", 0.9),
        ]

        return self._pattern_match(text, patterns, EntityType.DATE, "current_date")

    def _pattern_match(self, text: str, patterns: List[Tuple[str, float]],
                       entity_type: EntityType, source: str) -> List[DetectedEntity]:
        """Helper to run multiple regex patterns"""
        entities = []
        for pattern, confidence in patterns:
            for match in re.finditer(pattern, text):
                entities.append(DetectedEntity(
                    text=match.group(),
                    entity_type=entity_type,
                    start=match.start(),
                    end=match.end(),
                    confidence=confidence,
                    source=source
                ))
        return entities

    def _remove_overlaps(self, entities: List[DetectedEntity]) -> List[DetectedEntity]:
        """Remove overlapping entities, keeping highest confidence/longest"""
        if not entities:
            return entities

        # Sort by start position
        entities.sort(key=lambda e: (e.start, -e.end))

        result = []
        i = 0

        while i < len(entities):
            current = entities[i]
            j = i + 1

            # Check for overlaps with subsequent entities
            while j < len(entities):
                other = entities[j]

                # Check overlap
                if not (current.end <= other.start or other.end <= current.start):
                    # Overlap! Keep the better one
                    if other.confidence > current.confidence:
                        current = other
                    elif other.confidence == current.confidence and len(other.text) > len(current.text):
                        current = other
                    entities.pop(j)
                else:
                    j += 1

            result.append(current)
            i += 1

        return result

    def _deduplicate(self, entities: List[DetectedEntity]) -> List[DetectedEntity]:
        """Remove duplicate entities (same text, same position)"""
        seen = set()
        result = []

        for entity in entities:
            key = (entity.text.lower(), entity.start, entity.end)
            if key not in seen:
                seen.add(key)
                result.append(entity)

        return result
