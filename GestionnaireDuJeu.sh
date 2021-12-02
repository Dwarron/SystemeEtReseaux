#!/bin/bash

partieFini=false		#boolean pour connaitre l'état de la partie
cartes=()			#tableau qui représente les cartes du jeu au départ
cartesManche=()			#tableau qui représente les cartes du jeu durant une manche
nbJoueurs=0			#nombre de joueurs
nbRobots=0			#nombre de robots
nbJoueursTotaux=0		#nombre de participant totaux
declare -i manche=0		#nombre de manche de la partie, déclaré en integer (afin d'utiliser +=)
declare -i carteDistibue=0	#nombre de cartes distribuer dans la partie
declare -i carteRestante=0	#nombre de cartes restante dans une manche

initJoueurs()
{	
	#initialiser les joueurs
	echo Pour commencer, selectionner le nombre de joueur"("s")"  :
	read nbJoueurs
	
	if [ $nbJoueurs != 0 ];
	then
		for i in $(eval echo {1..$nbJoueurs});
		do	
			#ouvre un terminal en tache de fond pour chaque joueur
			gnome-terminal -- bash -c "./Joueurs.sh $i; bash" & #$i représente le numéro du joueurs
		done
	fi
}

initRobots()
{
	#initialiser les robots
	echo Ensuite selectionner le nombre de robot"("s")" :
	read nbRobots
	
	if [ $nbRobots != 0 ];
	then
		for i in $(eval echo {1..$nbRobots});
		do
			num=$(($nbJoueurs + $i))
			#ouvre un terminal pour chaque robot mais tous est automatisé
			gnome-terminal -- bash -c "./Robots.sh $num; bash" & #$num représente le numéro du robot
		done
	fi
}

#méthode qui remplie un tableau qui représente l'ensemble des cartes, de 1 a 100 au départ.
remplieCartes()
{
	for i in {1..100};
	do	
		cartes+=($i)
	done
}

#méthode qui va distribuer les cartes du jeu aux joueurs de la partie.
distribueCartes()
{
	#on incrémente le nombre de manche à chaque distribution de cartes au joueurs
	manche+=1 
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		#on vide le fichier qui contient les cartes pour un joueur
		echo "" > tmp/cartePartie
		
		#ici la manche permet de savoir combien de carte par joueurs on va distribuer
		for j in $(eval echo {1..$manche}); 
		do
			#on vérifie qu'il n'y est pas trop de carte distribué
			if [ $carteDistibue -gt $((98)) ];
			then
				exitPartie "Trop de carte distribué, fin de la partie."
			fi

			#indice aléatoire afin de recuperer une carte dans le jeu de cartes
			randomCarte=$(($RANDOM % $((99 - $carteDistibue)))) 
		
			#tableau qui va stocker toutes les cartes de la manche courante
			cartesManche+=(${cartes[$randomCarte]})
			
			#stock les cartes sélectionnées dans un fichier temporaire
			echo ${cartes[$randomCarte]} >> tmp/cartePartie
		
			#retire la carte
			retireCarte $randomCarte

			carteDistibue+=1
		done
		
		#ouvre un socket sur le port 9091 afin de recevoir les informations envoyées par un joueur
		echo "Cartes distribue" | nc -l -p 9091 
		
		#laisse le temps aux joueurs de récupérer leurs cartes
		sleep 1 
	done
	
	#le nombre de carte restante pour la manche courante
	carteRestante=$(($nbJoueursTotaux * $manche))
}

#méthode qui retire la carte passée en paramètre du tableau des cartes.
retireCarte()
{	
	carteRetirer=$1		 #indice de la carte a retirer 
	cartesTemp=()		 #tableau temporaire 
	
	#on vide le tableau de tout son contenu avant de le remplir
	unset cartesTemp 
	
	#on copie les cartes dans le tableau temporaire
	cartesTemp=("${cartes[@]}")
	
	#on vide le tableau des cartes de tout son contenu avant de le remplir
	unset cartes
	
	#récupération des bonnes valeur c'est-à-dire toutes sauf la carte retirer
	for x in $(eval echo {0..$((${#cartesTemp[*]} - 1))});
	do	
		if (( "$carteRetirer" != ${cartesTemp[$x]} ));
		then
			cartes+=(${cartesTemp[$x]})	
		fi
	done
}

#méthode qui envoie le top départ de la partie a tous les joueurs.
topDepart()
{
	for i in $(eval echo {1..$nbJoueursTotaux});
	do
		onAttend=true
		while [ $onAttend == "true" ]
		do
			#connexion aux sockets de chaque joueurs pour leurs signaler que la partie peut démarrer.
			echo "Vous avez recu le top depart." | nc localhost 9092 2> /dev/null & onAttend=false
		done
	done
}

#méthode qui permet de traiter les informations reçu par l'ensemble des joueurs.
traitementManche()
{
	carteAJouer=100		#représente la plus petite carte de la manche en cours
	carteCourante=0		#carte courante du joueur
	numParticipant=0	#numéro du participant
	
	#on parcours toutes les cartes de le manche et on cherche la plus petite carte
	carteAParcourir=$(( ${#cartesManche[*]} - 1 ))
	for i in $(eval echo {0..$carteAParcourir});
	do	
		if (( "${cartesManche[$i]}" < "$carteAJouer" ));
		then
			carteAJouer=${cartesManche[$i]}
		fi
	done
	
	#on attend la connexion d'un joueur, n'importe lequel pour traiter sa carte joué
	echo "Attente de connexion d'un joueur." | nc -l -p 9093 2> /dev/null 
	
	#récuperation de la carte jouer
	carteCourante=$(cat tmp/carteAJouer)
	echo "" > tmp/carteAJouer
	#récuperation du numéro du joueur
	numParticipant=$(cat tmp/numJoueur)
	echo "" > tmp/numJoueur

	#comparaison de la carte envoyée par le joueur avec la carte à jouer
	if [ "$carteCourante" == "$carteAJouer" ];
	then
		#on retire la carte des cartes de la manche
		cartesManche=( ${cartesManche[*]/$carteCourante} )	
		
		#écriture dans le fichier tmp/carteJouer qu'elle carte à était jouée et par qui
		echo "" > tmp/carteJouer
		echo "Carte $carteCourante joué par le participant n°$numParticipant" > tmp/carteJouer
		
		carteRestante=$((carteRestante - 1))
	else 	
		#la carte envoyée n'était pas la bonne donc on appelle la fonction exitPartie pour arrêter la partie
		exitPartie "Mauvaise carte joué, fin de la partie. Carte $carteCourante du participant n°$numParticipant"
	fi
}

#méthode qui permet de faire tourner la partie tant qu'elle n'est pas finie.
deroulementPartie()
{
	while [ $partieFini == "false" ]
	do
		#traite les informations de la partie
		traitementManche 
		
		#si les joueurs non plus de cartes on en redistribue
		if (( "$carteRestante" == 0 ));
		then
			unset cartesManche
			#on écrit redistribuer dans le fichier tmp/redistribuer pour que les joueurs reçoivent de nouvelles cartes
			echo Resdistribuer > tmp/redistribuer
			#on appelle la méthode de distribution des cartes
 			distribueCartes
 			#une fois les cartes redistribuer on vide le contenue du fichier
 			echo "" > tmp/redistribuer
 		fi;
	done
}

#méthode qui permet quand la partie est finie d'écrire un top 10 des parties dans le gestionnaire du jeu.
#ajoute également la partie courante terminée à l'ensemble du fichier.
classementPartie()
{	
	#on écrit dans le fichier Classement.txt le nombre de manche et le nombre de joueur 
	#l'option -e permet d'utiliser les "\t" qui représente une tabulation
	echo -e "$manche\t\t\t$nbJoueursTotaux" >> Classement.txt
	
	#on trie le fichier classement
	sort -n Classement.txt -o Classement.txt
	
	#on affiche dans le terminale du gestionnaire du jeu les titres des colonnes avec la commande "head" et le top 10 avec la commande "tail"
	echo "Voici le classement dans l'ordre croissant des partie qui on durer le plus longtemps"
	head -n 1  Classement.txt	
	tail -n 10 Classement.txt
}

#fonction qui permet d'arrêter la partie si une erreur a été détectée.
exitPartie()
{
	#affiche l'erreur qui fait stopper la partie dans le terminale du gestionnaire du jeux
	echo $1
	#écriture des informations d'arrêt de la partie dans le fichier tmp/finGame
	echo "fin" > tmp/finGame
	echo $1 >> tmp/finGame
	
	#comme la partie est terminée on déclenche l'affichage du classement
	classementPartie
	partieFini=true
}

#méthode qui démarre la partie.
startPartie()
{
	#avant de démarrer la partie on vide tous les fichier temporaire
	echo "" > tmp/finGame
	echo "" > tmp/cartePartie
	echo "" > tmp/carteAJouer
	echo "" > tmp/numJoueur
	echo ""	> tmp/redistribuer
	echo "" > tmp/pidParticipant

	#deuxième étape on remplit les cartes de la partie
	remplieCartes
	
	#par la suite on initialise les tous les joueurs de la partie
	initJoueurs
	initRobots
	
	nbJoueursTotaux=$(($nbJoueurs + $nbRobots))
	#echo Nous avons donc $nbJoueursTotaux participants pour cette partie
	
	#on distribue les cartes une première fois avant le top départ
	distribueCartes
	
	#envoie le top départ après la distribution des cartes à tous les joueurs
	topDepart
	
	#ici on lance le déroulement de la partie  
	deroulementPartie
}

#on lance la méthode qui démarre la partie qui va appeler en cascade toutes les autres fonctions
startPartie
