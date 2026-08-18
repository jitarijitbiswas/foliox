import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/primary_footer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<void> _pickPhoto(Box<String> settings, String accountId) async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (photo == null) return;
    await settings.put('profile_image:$accountId', base64Encode(await photo.readAsBytes()));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = Hive.box<String>('foliox_settings');
    final name = settings.get('local_account_name') ?? 'Paper Trader';
    final identifier = settings.get('active_account_id') ?? '';
    final photo = settings.get('profile_image:$identifier');
    final photoBytes = photo == null ? null : base64Decode(photo);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      bottomNavigationBar: const PrimaryFooter(selectedIndex: 5),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundImage: photoBytes == null ? null : MemoryImage(photoBytes),
                  child: photoBytes == null ? Text(
                    name.isEmpty ? 'P' : name.trim().substring(0, 1).toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ) : null,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: IconButton.filledTonal(
                    tooltip: 'Choose profile photo',
                    onPressed: () => _pickPhoto(settings, identifier),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => _pickPhoto(settings, identifier),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: const Text('Add or change photo'),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (identifier.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              identifier,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 28),
          const _ProfileSectionTitle('Paper trading account'),
          Card(
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.account_balance_wallet_outlined),
                  title: Text('Virtual trading account'),
                  subtitle: Text('Your orders and portfolio remain on this device.'),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Privacy'),
                  subtitle: Text('No real money or brokerage account is connected.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _ProfileSectionTitle('Session'),
          FilledButton.tonalIcon(
            onPressed: () async {
              await settings.delete('active_account_id');
              await settings.delete('local_account_name');
              if (context.mounted) context.go('/onboarding');
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out of this device'),
          ),
        ],
      ),
    );
  }
}

class _ProfileSectionTitle extends StatelessWidget {
  const _ProfileSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
