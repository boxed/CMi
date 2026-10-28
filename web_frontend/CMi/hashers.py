import hashlib
from django.contrib.auth.hashers import BasePasswordHasher
from django.utils.crypto import constant_time_compare


class LegacySHA1PasswordHasher(BasePasswordHasher):
    """
    Verifies the "sha1$salt$hash" passwords stored by old Django versions. Django rehashes them with
    the default hasher on the first successful login, so this is only needed to read old databases.
    """
    algorithm = 'sha1'

    def encode(self, password, salt):
        return '%s$%s$%s' % (self.algorithm, salt, hashlib.sha1((salt + password).encode()).hexdigest())

    def decode(self, encoded):
        algorithm, salt, hash = encoded.split('$', 2)
        return {'algorithm': algorithm, 'hash': hash, 'salt': salt}

    def verify(self, password, encoded):
        decoded = self.decode(encoded)
        return constant_time_compare(encoded, self.encode(password, decoded['salt']))

    def safe_summary(self, encoded):
        decoded = self.decode(encoded)
        return {'algorithm': decoded['algorithm'], 'salt': decoded['salt'][:2] + '...', 'hash': decoded['hash'][:6] + '...'}

    def harden_runtime(self, password, encoded):
        pass
