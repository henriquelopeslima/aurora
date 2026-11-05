<?php

declare(strict_types=1);

namespace App\Tests\Functional;

use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;
use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;
use Symfony\Component\Yaml\Yaml;

use function Symfony\Component\String\s;

class TranslationsTest extends KernelTestCase
{
    private const array TRANSLATION_FILES = [
        'translations/messages.pt-br.yaml',
        'translations/messages.en.yaml',
        'translations/messages.es.yaml',
    ];

    protected function setUp(): void
    {
        self::bootKernel();
    }

    public function testTranslationsFilesExists(): void
    {
        foreach (self::TRANSLATION_FILES as $file) {
            $this->assertFileExists(self::$kernel->getProjectDir().'/'.$file);
        }
    }

    public function testTranslationsHaveSameKeys(): void
    {
        $ptBRTranslation = Yaml::parseFile(self::$kernel->getProjectDir().'/'.self::TRANSLATION_FILES[0]);
        $translations = array_slice(self::TRANSLATION_FILES, 1);

        foreach ($translations as $file) {
            $translationArray = Yaml::parseFile(self::$kernel->getProjectDir().'/'.$file);
            $this->testKeyExists($ptBRTranslation, $translationArray, $file);
        }
    }

    // Um import sem chave quebra o grafo de módulos inteiro (navbar inclusa), não só o script que importa.
    public function testConstantsImportedByJsHaveTranslationKeys(): void
    {
        $projectDir = self::$kernel->getProjectDir();
        $constants = array_map(
            fn (string $key) => s($key)->ascii()->snake()->upper()->replaceMatches('/^(\d)/', '_$1')->toString(),
            array_keys($this->flatten(Yaml::parseFile($projectDir.'/'.self::TRANSLATION_FILES[0])))
        );

        $files = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($projectDir.'/assets/js'));
        foreach ($files as $file) {
            if ('js' !== $file->getExtension()) {
                continue;
            }

            preg_match_all('/import\s*\{([^}]+)\}\s*from\s*[\'"][.\/]*translator(?:\.js)?[\'"]/', file_get_contents($file->getPathname()), $matches);
            foreach (array_map('trim', explode(',', implode(',', $matches[1]))) as $imported) {
                if ('' === $imported || 'trans' === $imported) {
                    continue;
                }

                $this->assertContains($imported, $constants, "{$file->getFilename()} imports $imported, which has no translation key.");
            }
        }
    }

    private function flatten(array $translations, string $prefix = ''): array
    {
        $flat = [];
        foreach ($translations as $key => $value) {
            $fullKey = '' === $prefix ? (string) $key : $prefix.'.'.$key;
            $flat += is_array($value) ? $this->flatten($value, $fullKey) : [$fullKey => $value];
        }

        return $flat;
    }

    private function testKeyExists(array $firstArray, array $secondArray, string $fileName = '', string $prefix = ''): void
    {
        foreach ($firstArray as $key => $value) {
            $fullKey = $prefix ? $prefix.'.'.$key : $key;
            $this->assertArrayHasKey(
                $key,
                $secondArray,
                "The key $fullKey is missing in the file $fileName."
            );

            if (is_array($value)) {
                $this->testKeyExists($value, $secondArray[$key] ?? [], $fileName, $fullKey);
            }
        }
    }
}
