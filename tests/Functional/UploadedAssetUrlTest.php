<?php

declare(strict_types=1);

namespace App\Tests\Functional;

use Symfony\Bundle\FrameworkBundle\Test\KernelTestCase;
use Symfony\Component\Asset\Packages;

class UploadedAssetUrlTest extends KernelTestCase
{
    private string $file;

    protected function setUp(): void
    {
        self::bootKernel();
        $this->file = self::$kernel->getProjectDir().'/assets/uploads/users/images/profile/uploaded-asset-url-test.jpg';
        @mkdir(dirname($this->file), recursive: true);
        file_put_contents($this->file, 'x');
    }

    protected function tearDown(): void
    {
        @unlink($this->file);
        parent::tearDown();
    }

    // Uploads chegam depois do asset-map:compile; uma URL versionada em /assets/ daria 404 em prod.
    public function testUploadedFileUrlIsNotRoutedThroughAssetMapper(): void
    {
        $packages = self::getContainer()->get(Packages::class);

        $path = '/uploads/users/images/profile/uploaded-asset-url-test.jpg';

        $this->assertSame($path, $packages->getUrl($path));
    }
}
