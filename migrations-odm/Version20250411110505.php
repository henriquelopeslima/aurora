<?php

declare(strict_types=1);

namespace DoctrineMigrationsOdm;

use App\DataFixtures\Entity\UserFixtures;
use App\Document\NotificationDocument;
use DateTime;
use Doctrine\Bundle\FixturesBundle\Fixture;
use Doctrine\ODM\MongoDB\DocumentManager;

final class Version20250411110505
{
    public function up(DocumentManager $dm): void
    {
        // Dado de teste que depende das fixtures (require-dev): em prod o pacote não existe.
        if (!class_exists(Fixture::class)) {
            return;
        }

        $notificationDocument = new NotificationDocument();
        $notificationDocument->setSender(UserFixtures::USER_ID_1);
        $notificationDocument->setTarget(UserFixtures::USER_ID_2);
        $notificationDocument->setVisited(false);
        $notificationDocument->setContext('Test context');
        $notificationDocument->setContent('Test notification content');
        $notificationDocument->setCreatedAt(new DateTime());
        $notificationDocument->setVisitedAt(null);

        $dm->persist($notificationDocument);
        $dm->flush();
    }

    public function down(DocumentManager $dm): void
    {
        $dm->getDocumentCollection(NotificationDocument::class)->drop();
    }
}
